import os
import uuid
import logging
import base64
import json
from pathlib import Path
from typing import Optional, List, AsyncGenerator
from datetime import datetime
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from PIL import Image
import io
from queue import Queue
import asyncio
import requests
import re
import ast

# Configure logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)

# --- AIRFLOW CONFIGURATION ---
AIRFLOW_HOST = os.getenv("AIRFLOW_HOST")
AIRFLOW_DAG_ID = "image_processor_v1"
AIRFLOW_TASK_ID = "generate_final_report"
AIRFLOW_API_KEY = os.getenv("AIRFLOW_API_KEY") 
AIRFLOW_HEADERS = {
    "Authorization": f"Basic {AIRFLOW_API_KEY}",
    "Content-Type": "application/json"
}

app = FastAPI(title="Image Saver API", version="0.1.0")

# Add CORS middleware for OpenWebUI compatibility
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Configuration
SHARED_STORAGE_PATH = os.getenv("SHARED_STORAGE_PATH", "/appz/shared/images")
MAX_FILE_SIZE = 10 * 1024 * 1024  # 10MB
ALLOWED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp"}

# Ensure storage directory exists
Path(SHARED_STORAGE_PATH).mkdir(parents=True, exist_ok=True)
logger.info(f"Image storage path: {SHARED_STORAGE_PATH}")


class ChatMessage(BaseModel):
    role: str
    content: str
    images: Optional[List[str]] = None


class ChatRequest(BaseModel):
    model: str
    messages: List[ChatMessage]
    stream: bool = False


class StreamChunk(BaseModel):
    model: str
    created_at: str
    message: ChatMessage
    done: bool


class FinalResponse(BaseModel):
    model: str
    created_at: str
    message: ChatMessage
    done: bool
    done_reason: str
    total_duration: int
    load_duration: int
    prompt_eval_count: int
    prompt_eval_duration: int
    eval_count: int
    eval_duration: int


def verify_and_decode_image(base64_image: str) -> tuple:
    """Verify and decode a base64 image."""
    try:
        image_bytes = base64.b64decode(base64_image)
        image = Image.open(io.BytesIO(image_bytes))
        image.verify()
        
        image = Image.open(io.BytesIO(image_bytes))
        metadata = {
            "format": image.format,
            "mode": image.mode,
            "width": image.width,
            "height": image.height,
            "size_bytes": len(image_bytes)
        }
        
        logger.info(f"Image verified: {metadata}")
        return image_bytes, metadata
    except Exception as e:
        logger.error(f"Image verification failed: {str(e)}")
        raise ValueError(f"Invalid image: {str(e)}")


def save_image(image_bytes: bytes, user_id: str, metadata: dict) -> dict:
    """Save image to shared storage."""
    try:
        format_to_ext = {
            "JPEG": ".jpg", "PNG": ".png", "GIF": ".gif",
            "BMP": ".bmp", "WEBP": ".webp"
        }
        file_ext = format_to_ext.get(metadata.get("format", "PNG"), ".png")
        
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        unique_id = str(uuid.uuid4())[:8]
        filename = f"img_{timestamp}_{unique_id}{file_ext}"
        
        user_dir = Path(SHARED_STORAGE_PATH) / user_id
        user_dir.mkdir(parents=True, exist_ok=True)
        
        file_path = user_dir / filename
        with open(file_path, "wb") as f:
            f.write(image_bytes)
        
        relative_path = str(file_path.relative_to(SHARED_STORAGE_PATH))
        logger.info(f"Image saved: {relative_path}")
        
        return {
            "filename": filename,
            "path": str(file_path),
            "relative_path": relative_path,
            "size_bytes": len(image_bytes),
            "saved_at": datetime.now().isoformat()
        }
    except Exception as e:
        logger.error(f"Failed to save image: {str(e)}")
        raise


def map_log_to_friendly_status(line: str) -> Optional[str]:
    """
    Translates raw Airflow logs into friendly user status messages.
    Returns None if the line is system noise.
    """
    # 1. Map Task Starts to Phases
    if "task_id=fetch_and_inspect_image" in line or "Executing <Task(PythonOperator): fetch_and_inspect_image>" in line:
        return "📂 Fetching image from storage..."
    
    if "task_id=generate_final_report" in line or "Executing <Task(PythonOperator): generate_final_report>" in line:
        return "📝 Verifying data and preparing response..."

    # 2. Map Your Custom DAG Logs (The logging.info calls you wrote)
    if "STEP 1: Fetching" in line:
        return "🔍 Inspecting file metadata..."
    
    if "Image found" in line:
        return "✅ Image verification successful."
    
    if "File not found" in line:
        return "❌ Error: Image not found."

    # 3. Map Completion
    if "Marking task as SUCCESS" in line:
        return None # Skip this, we'll let the next task start message handle the transition

    return None

def get_airflow_logs(run_id: str, try_number: int) -> list:
    """Fetches and cleans logs for the specific task run."""
    url = f"{AIRFLOW_HOST}/dags/{AIRFLOW_DAG_ID}/dagRuns/{run_id}/taskInstances/{AIRFLOW_TASK_ID}/logs/{try_number}"
    try:
        res = requests.get(url, headers=AIRFLOW_HEADERS, timeout=5)
        if res.status_code == 200:
            return res.text.split('\n')
    except Exception as e:
        logger.error(f"Failed to fetch logs: {e}")
    return []

def get_current_try_number(run_id: str) -> int:
    """Gets current attempt number."""
    url = f"{AIRFLOW_HOST}/dags/{AIRFLOW_DAG_ID}/dagRuns/{run_id}/taskInstances/{AIRFLOW_TASK_ID}"
    try:
        res = requests.get(url, headers=AIRFLOW_HEADERS)
        if res.status_code == 200:
            return res.json().get('try_number', 1)
    except:
        pass
    return 1

async def generate_stream_response(model: str, image_path: str, original_prompt: str) -> AsyncGenerator[str, None]:
    """Streaming response with Airflow logs inside a <think> block."""
    
    # --- Start the visible <think> block ---
    think_open = "<think>\n"
    yield StreamChunk(
        model=model,
        created_at=datetime.now().isoformat(),
        message=ChatMessage(role="assistant", content=think_open),
        done=False
    ).model_dump_json() + "\n"
    try:
        # 1. Trigger the DAG
        trigger_url = f"{AIRFLOW_HOST}/dags/{AIRFLOW_DAG_ID}/dagRuns"
        payload = {"conf": {"image_path": image_path}}

        # Stream initial status to think block
        yield StreamChunk(
            model=model,
            created_at=datetime.now().isoformat(),
            message=ChatMessage(role="assistant", content=f"🚀 Triggering Image Processor DAG for: {os.path.basename(image_path)}...\n"),
            done=False
        ).model_dump_json() + "\n"

        resp = requests.post(trigger_url, headers=AIRFLOW_HEADERS, json=payload, timeout=10)
        resp.raise_for_status()
        dag_run_id = resp.json()['dag_run_id']

        # 2. Poll Status & Stream Business Logic Logs
        status = "running"
        last_log_idx = 0
        seen_messages = set() # To prevent repeating the same status
        
        while status in ["queued", "running"]:
            await asyncio.sleep(2) # Polling interval
            
            # Check Status
            status_resp = requests.get(f"{AIRFLOW_HOST}/dags/{AIRFLOW_DAG_ID}/dagRuns/{dag_run_id}", headers=AIRFLOW_HEADERS)
            if status_resp.status_code == 200:
                status = status_resp.json()['state']
            
            # Fetch and Stream Logs
            try_num = get_current_try_number(dag_run_id)
            raw_lines = get_airflow_logs(dag_run_id, try_num)
            
            if len(raw_lines) > last_log_idx:
                new_lines = raw_lines[last_log_idx:]
                for line in new_lines:
                    # Clean the log using the helper from previous step
                    clean_msg  = map_log_to_friendly_status(line)
                    if clean_msg and clean_msg not in seen_messages:
                        # Stream the specific log line into the think block
                        seen_messages.add(clean_msg)
                        yield StreamChunk(
                            model=model,
                            created_at=datetime.now().isoformat(),
                            message=ChatMessage(role="assistant", content=f"{clean_msg}\n"),
                            done=False
                        ).model_dump_json() + "\n"
                last_log_idx = len(raw_lines)

        # 3. Fetch XCom Result (Hidden Logic)
        xcom_url = f"{AIRFLOW_HOST}/dags/{AIRFLOW_DAG_ID}/dagRuns/{dag_run_id}/taskInstances/{AIRFLOW_TASK_ID}/xcomEntries/return_value"
        xcom_resp = requests.get(xcom_url, headers=AIRFLOW_HEADERS)
        
        final_content = ""
        if xcom_resp.status_code == 200:
            raw_val = xcom_resp.json()['value']
            data = ast.literal_eval(raw_val) if isinstance(raw_val, str) else raw_val
            
            if data.get("status") == "success":
                final_content = (
                    f"✅ **Processing Complete**\n\n"
                    f"The image `{os.path.basename(data.get('image_path', ''))}` was verified successfully.\n"
                    f"**Details:**\n"
                    f"* File Size: {data.get('file_size')} bytes\n"
                    f"* Verification: {data.get('message')}"
                )
            else:
                final_content = f"❌ **Processing Failed**: {data.get('message')}"
        else:
            final_content = f"⚠️ DAG finished ({status}), but failed to retrieve XCom results."

    except Exception as e:
        logger.error(f"Workflow failed: {str(e)}")
        yield StreamChunk(
            model=model,
            created_at=datetime.now().isoformat(),
            message=ChatMessage(role="assistant", content=f"Error executing workflow: {str(e)}\n"),
            done=False
        ).model_dump_json() + "\n"
        final_content = f"System Error: {str(e)}"
        
    # --- Close the <think> block ---
    think_close = "\n</think>\n\n"
    yield StreamChunk(
        model=model,
        created_at=datetime.now().isoformat(),
        message=ChatMessage(role="assistant", content=think_close),
        done=False
    ).model_dump_json() + "\n"

    # 4. Stream the Final Response
    words = final_content.split()
    chunk_size = 5
    
    for i in range(0, len(words), chunk_size):
        chunk_words = words[i:i + chunk_size]
        chunk_content = " " + " ".join(chunk_words) if i > 0 else " ".join(chunk_words)

        yield StreamChunk(
            model=model,
            created_at=datetime.now().isoformat(),
            message=ChatMessage(role="assistant", content=chunk_content),
            done=False
        ).model_dump_json() + "\n"
        await asyncio.sleep(0.05)
    
    # --- Final done chunk ---
    final = FinalResponse(
        model=model,
        created_at=datetime.now().isoformat(),
        message=ChatMessage(role="assistant", content=""),
        done=True,
        done_reason="stop",
        total_duration=0,
        load_duration=0,
        prompt_eval_count=0,
        prompt_eval_duration=0,
        eval_count=0,
        eval_duration=0
    )
    yield final.model_dump_json() + "\n"


@app.get("/")
async def root():
    return {"message": "Ollama is running"}


@app.head("/")
async def root_head():
    return {}


@app.get("/api/tags")
async def list_models():
    return {
        "models": [
            {
                "name": "clipfoundry.ai Pixora:0.3",
                "model": "Pixora:0.3",
                "modified_at": datetime.now().isoformat(),
                "size": 1024
            }
        ]
    }


@app.get("/api/version")
async def get_version():
    return {"version": "0.1.0"}


@app.post("/api/chat")
async def chat_dag(request: Request):
    try:
        body = await request.json()
        headers = dict(request.headers)
        
        user_email = headers.get('x-openwebui-user-email', 'anonymous@test.com')
        user_id = headers.get('x-openwebui-user-id', 'anonymous')
        user_name = headers.get('x-openwebui-user-name', 'Anonymous User')
        
        logger.info(f"Chat request from user: {user_email} (ID: {user_id})")
        
        messages = body.get("messages", [])
        model = body.get("model", "image-saver:test")
        stream = body.get("stream", False)
        
        if not messages:
            raise HTTPException(status_code=400, detail="Messages are required")
        
        last_message = messages[-1]
        user_content = last_message.get("content", "").strip()
        images = last_message.get("images", [])
        
        logger.info(f"Processing message with {len(images)} image(s), stream={stream}")
        
        response_parts = []
        saved_images = []
        last_saved_path = None  # Track the path for the DAG
        
        if images:
            response_parts.append(f"👤 Hello {user_name}! I received {len(images)} image(s).\n")
            
            for idx, base64_image in enumerate(images, 1):
                try:
                    image_bytes, metadata = verify_and_decode_image(base64_image)
                    save_info = save_image(image_bytes, user_id, metadata)
                    saved_images.append(save_info)
                    # Capture the absolute path for the DAG
                    last_saved_path = save_info['path']
                    
                    response_parts.append(
                        f"\n📸 **Image {idx} Saved Successfully:**\n"
                        f"   • Format: {metadata['format']}\n"
                        f"   • Dimensions: {metadata['width']}x{metadata['height']} pixels\n"
                        f"   • Size: {metadata['size_bytes'] / 1024:.2f} KB\n"
                        f"   • Filename: `{save_info['filename']}`\n"
                        f"   • Path: `{save_info['relative_path']}`\n"
                    )
                except Exception as e:
                    logger.error(f"Error processing image {idx}: {str(e)}")
                    response_parts.append(f"\n❌ **Image {idx} Error:** {str(e)}\n")
            
            total_size = sum(img['size_bytes'] for img in saved_images)
            response_parts.append(
                f"\n✅ **Summary:**\n"
                f"   • Images saved: {len(saved_images)}/{len(images)}\n"
                f"   • Total size: {total_size / 1024:.2f} KB\n"
                f"   • Storage: `{SHARED_STORAGE_PATH}/{user_id}/`\n"
            )
        else:
            response_parts.append(
                f"👋 Hello {user_name}!\n\n"
                f"I'm the **Image Saver Assistant**. Send me images and I'll save them to shared storage.\n\n"
                f"📝 Your message: {user_content or 'No text, waiting for images...'}\n\n"
                f"💡 **How to use:** Attach images and send!"
            )
        
        response_content = "".join(response_parts)
        
        if stream and last_saved_path:
            # TRIGGER DAG FLOW
            # We ignore the initial summary text for the stream and let the generator handle the response
            return StreamingResponse(
                generate_stream_response(model, last_saved_path, user_content),
                media_type="application/x-ndjson"
            )
        elif stream and not last_saved_path:
             # Fallback for text-only streaming
             return StreamingResponse(
                generate_stream_response(model, "", user_content), # Handle empty path case in generator if needed
                media_type="application/x-ndjson"
            )
        else:
            # Non-streaming: no thinking delay needed
            return JSONResponse(content=FinalResponse(
                model=model,
                created_at=datetime.now().isoformat(),
                message=ChatMessage(role="assistant", content=response_content),
                done=True,
                done_reason="stop",
                total_duration=1000000000,
                load_duration=1000000,
                prompt_eval_count=10,
                prompt_eval_duration=500000000,
                eval_count=100,
                eval_duration=500000000
            ).model_dump())
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error in chat endpoint: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Error: {str(e)}")

@app.post("/api/generate")
async def generate(request: Request):
    body = await request.json()
    model = body.get("model", "image-saver:test")
    prompt = body.get("prompt", "")
    stream = body.get("stream", False)
    
    response_text = f"This is the image-saver model. Use /api/chat endpoint to send images. Your prompt: {prompt}"
    
    if stream:
        return StreamingResponse(
            generate_stream_response(model, response_text),
            media_type="application/x-ndjson"
        )
    else:
        return JSONResponse(content={
            "model": model,
            "created_at": datetime.now().isoformat(),
            "response": response_text,
            "done": True
        })


@app.get("/api/images/list")
async def list_saved_images(user_id: Optional[str] = None):
    try:
        search_path = Path(SHARED_STORAGE_PATH) / user_id if user_id else Path(SHARED_STORAGE_PATH)
        
        if not search_path.exists():
            return {"images": [], "count": 0, "storage_path": str(search_path)}
        
        images = []
        for file_path in search_path.rglob("*"):
            if file_path.is_file() and file_path.suffix.lower() in ALLOWED_EXTENSIONS:
                stat = file_path.stat()
                images.append({
                    "filename": file_path.name,
                    "relative_path": str(file_path.relative_to(SHARED_STORAGE_PATH)),
                    "size_bytes": stat.st_size,
                    "size_kb": round(stat.st_size / 1024, 2),
                    "modified_at": datetime.fromtimestamp(stat.st_mtime).isoformat(),
                    "user_folder": file_path.parent.name
                })
        
        images.sort(key=lambda x: x['modified_at'], reverse=True)
        total_size = sum(img['size_bytes'] for img in images)
        
        return {
            "images": images,
            "count": len(images),
            "total_size_kb": round(total_size / 1024, 2),
            "total_size_mb": round(total_size / (1024 * 1024), 2),
            "storage_path": str(search_path)
        }
    except Exception as e:
        logger.error(f"Error listing images: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Error: {str(e)}")


@app.get("/api/images/stats")
async def get_storage_stats():
    try:
        storage_path = Path(SHARED_STORAGE_PATH)
        
        if not storage_path.exists():
            return {"status": "storage_not_initialized", "path": str(storage_path)}
        
        total_files = 0
        total_size = 0
        users = set()
        
        for file_path in storage_path.rglob("*"):
            if file_path.is_file() and file_path.suffix.lower() in ALLOWED_EXTENSIONS:
                total_files += 1
                total_size += file_path.stat().st_size
                try:
                    user_folder = file_path.relative_to(storage_path).parts[0]
                    users.add(user_folder)
                except IndexError:
                    pass
        
        return {
            "status": "active",
            "storage_path": str(storage_path),
            "total_images": total_files,
            "total_users": len(users),
            "total_size_bytes": total_size,
            "total_size_mb": round(total_size / (1024 * 1024), 2),
            "users": sorted(list(users))
        }
    except Exception as e:
        logger.error(f"Error getting stats: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Error: {str(e)}")


@app.get("/health")
@app.get("/api/health")
async def health_check():
    storage_path = Path(SHARED_STORAGE_PATH)
    is_accessible = storage_path.exists() and os.access(storage_path, os.W_OK)
    
    return {
        "status": "healthy" if is_accessible else "unhealthy",
        "storage_accessible": is_accessible,
        "storage_path": str(storage_path),
        "timestamp": datetime.now().isoformat()
    }


if __name__ == "__main__":
    import uvicorn
    logger.info("=" * 60)
    logger.info("Starting Image Saver API (Ollama Compatible)")
    logger.info(f"Storage path: {SHARED_STORAGE_PATH}")
    logger.info("=" * 60)
    uvicorn.run(app, host="0.0.0.0", port=8082, log_level="info")