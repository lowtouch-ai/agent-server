import os
import uuid
import logging
import base64
import json
from pathlib import Path
from typing import Optional, List, AsyncGenerator, Dict, Any
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
import httpx
import shutil

# Configure logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)

# --- AIRFLOW CONFIGURATION ---
AIRFLOW_HOST = os.getenv("AIRFLOW_HOST")
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
SHARED_STORAGE_PATH = os.getenv("SHARED_STORAGE_PATH")
VIDEO_OUTPUT_DIR = os.getenv("VIDEO_OUTPUT_DIR")
MAX_FILE_SIZE = 10 * 1024 * 1024  # 10MB
ALLOWED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp"}

# Ensure storage directory exists
Path(SHARED_STORAGE_PATH).mkdir(parents=True, exist_ok=True)
Path(VIDEO_OUTPUT_DIR).mkdir(parents=True, exist_ok=True)
logger.info(f"Image storage path: {SHARED_STORAGE_PATH}")
logger.info(f"Video output path: {VIDEO_OUTPUT_DIR}")


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

def save_video_to_static_dir(source_video_path: str) -> str:
    """Save or copy the video to the static videos directory and return the relative path."""
    try:
        if not Path(source_video_path).exists():
            raise ValueError(f"Source video path does not exist: {source_video_path}")
        
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        unique_id = str(uuid.uuid4())[:8]
        filename = f"video_{timestamp}_{unique_id}.mp4"  # Assuming MP4; adjust if needed
        
        target_path = Path(VIDEO_OUTPUT_DIR) / filename
        shutil.copy2(source_video_path, target_path)  # Copy to preserve metadata
        
        relative_path = f"/static/videos/{filename}"
        logger.info(f"Video saved/copied to: {relative_path}")
        
        return relative_path
    except Exception as e:
        logger.error(f"Failed to save video to static dir: {str(e)}")
        raise

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
    Strictly filters logs to only return messages prefixed with 'Thinking: '.
    """
    line = line.strip()
    if not line:
        return None
    
    # We look for the tag regardless of log levels (INFO, WARNING, etc.)
    TOKEN = "Thinking:"
    if TOKEN in line:
        # Split on the token and return everything after it
        return line.split(TOKEN, 1)[1].strip()

    return None

def get_airflow_logs(run_id: str, try_number: int, dag_id: str, task_id: str) -> list:
    """Fetches and cleans logs for the specific task run."""
    url = f"{AIRFLOW_HOST}/dags/{dag_id}/dagRuns/{run_id}/taskInstances/{task_id}/logs/{try_number}"
    try:
        res = requests.get(url, headers=AIRFLOW_HEADERS, timeout=5)
        if res.status_code == 200:
            return res.text.split('\n')
    except Exception as e:
        logger.error(f"Failed to fetch logs: {e}")
    return []

def get_current_try_number(run_id: str, dag_id: str, task_id: str) -> int:
    """Gets current attempt number."""
    url = f"{AIRFLOW_HOST}/dags/{dag_id}/dagRuns/{run_id}/taskInstances/{task_id}"
    try:
        res = requests.get(url, headers=AIRFLOW_HEADERS)
        if res.status_code == 200:
            return res.json().get('try_number', 1)
    except:
        pass
    return 1

async def generate_stream_response(model: str, image_paths: List[str], original_prompt: str, dag_id: str, headers: Dict[str, str], messages: List[Dict[str, Any]], user_email: str, user_id: str, user_name: str, user_role: str, vault_user: str, vault_keys: str) -> AsyncGenerator[str, None]:
    """Streaming response with Airflow logs inside a <think> block."""
    
    request_id = headers.get("x-openwebui-request-id", str(uuid.uuid4()))
    # --- Start the visible <think> block ---
    think_open = "<think>\n"
    yield StreamChunk(
        model=model,
        created_at=datetime.now().isoformat(),
        message=ChatMessage(role="assistant", content=think_open),
        done=False
    ).model_dump_json() + "\n"
    try:
        # Construct agent_headers
        agent_headers = {
            "X-LTAI-User": user_email,
            "X-LTAI-Agent": model,
            "X-LTAI-Model": model,
            "X-LTAI-User-ID": user_id,
            "X-LTAI-User-Role": user_role,
            "X-LTAI-User-Name": user_name,
            "X-LTAI-Vault-User": vault_user,
            "X-LTAI-Vault-Keys": vault_keys,
            "X-LTAI-Request-ID": request_id
        }
        # Construct chat_inputs (adapt to existing structure)
        last_message = messages[-1] if messages else {}
        # Map all paths to the file object structure
        files_list = [{"path": p, "type": "image"} for p in image_paths]
        chat_inputs = {
            "message": last_message.get("content", ""),
            "history": messages[:-1] if len(messages) > 1 else [],
            "files": files_list,
            "args": {"image_path": image_paths[0]} if image_paths else {},  # Preserve for DAG compatibility
            "timestamp": datetime.utcnow().isoformat()
        }
        # Final payload
        dag_payload = {
            "agent_headers": agent_headers,
            "chat_inputs": chat_inputs
        }
        # 1. Trigger the DAG
        trigger_url = f"{AIRFLOW_HOST}/dags/{dag_id}/dagRuns"  # Use mapped dag_id
        payload = {"conf": dag_payload}
        resp = requests.post(trigger_url, headers=AIRFLOW_HEADERS, json=payload, timeout=10)
        resp.raise_for_status()
        dag_run_id = resp.json()['dag_run_id']

        # Get all task instances
        ti_url = f"{AIRFLOW_HOST}/dags/{dag_id}/dagRuns/{dag_run_id}/taskInstances"
        ti_resp = requests.get(ti_url, headers=AIRFLOW_HEADERS)
        task_instances = ti_resp.json().get("task_instances", []) if ti_resp.status_code == 200 else []

        # Track log progress per task
        last_log_counts = {ti["task_id"]: 0 for ti in task_instances}
        started_tasks = set()     # Tracks 'Started {task}'
        completed_tasks = set()   # Tracks 'Completed {task}'

        status = "running"
        while status in ["queued", "running"]:
            await asyncio.sleep(2) # Polling interval

            # Refresh run state
            run_resp = requests.get(f"{AIRFLOW_HOST}/dags/{dag_id}/dagRuns/{dag_run_id}", headers=AIRFLOW_HEADERS)
            if run_resp.status_code == 200:
                status = run_resp.json().get("state", "running")

            # Poll each task
            for ti in task_instances:
                task_id = ti["task_id"]
                task_url = f"{AIRFLOW_HOST}/dags/{dag_id}/dagRuns/{dag_run_id}/taskInstances/{task_id}"
                task_resp = requests.get(task_url, headers=AIRFLOW_HEADERS)
                if task_resp.status_code != 200:
                    continue
                task_info = task_resp.json()
                current_state = task_info.get("state")
                try_num = task_info.get("try_number", 1)

                # Emit "started" only once
                # We check if task is running/queued/success and hasn't been announced yet
                is_active = current_state in ["running", "queued", "success", "failed", "upstream_failed"]
                if is_active and task_id not in started_tasks:
                    yield StreamChunk(
                        model=model,
                        created_at=datetime.now().isoformat(),
                        message=ChatMessage(role="assistant", content=f"Started `{task_id}`\n"),
                        done=False
                    ).model_dump_json() + "\n"
                    started_tasks.add(task_id)

                # Stream new logs
                logs = get_airflow_logs(dag_run_id, try_num, dag_id, task_id)
                new_logs = logs[last_log_counts[task_id]:]
                last_log_counts[task_id] = len(logs)

                for line in new_logs:
                    clean = map_log_to_friendly_status(line)
                    if clean:
                        yield StreamChunk(
                            model=model,
                            created_at=datetime.now().isoformat(),
                            message=ChatMessage(role="assistant", content=f"{clean}\n"),
                            done=False
                        ).model_dump_json() + "\n"

                # 2. Emit "Completed" ONCE when task succeeds/fails
                if current_state in ["success", "failed", "skipped"] and task_id not in completed_tasks:
                    yield StreamChunk(
                        model=model,
                        created_at=datetime.now().isoformat(),
                        message=ChatMessage(role="assistant", content=f"Completed `{task_id}`\n"),
                        done=False
                    ).model_dump_json() + "\n"
                    last_success_task = task_id
                    completed_tasks.add(task_id)

        # Final XCom from last successful task
        final_content = "DAG completed but no result found."
        if last_success_task:
            xcom_url = f"{AIRFLOW_HOST}/dags/{dag_id}/dagRuns/{dag_run_id}/taskInstances/{last_success_task}/xcomEntries/return_value"
            xcom_resp = requests.get(xcom_url, headers=AIRFLOW_HEADERS)
            if xcom_resp.status_code == 200:
                raw = xcom_resp.json().get("value")
                data = ast.literal_eval(raw) if isinstance(raw, str) else raw
                
                if isinstance(data, dict) and data.get("status") == "success":
                    
                    # --- NEW LOGIC: JUST PRINT THE DAG'S OUTPUT ---
                    if "markdown_output" in data:
                        final_content = data["markdown_output"]
                    
                    elif "video_path" in data:
                        vid_path = data["video_path"]
                        video_url = save_video_to_static_dir(vid_path)
                        
                        final_content = (
                            f"### 🎬 Video Ready!\n\n"
                            f"Your video has been generated successfully.\n\n"
                            f'<video width="100%" controls>\n'
                            f'  <source src="{video_url}" type="video/mp4">\n'
                            f'  Your browser does not support the video tag.\n'
                            f'</video>\n'
                            f"[**⬇️ Click here to Download**]({video_url})"
                        )
                    
                    # Fallback for Image Saver
                    elif "file_size" in data:
                        final_content = f"**Image Saved**\nFile: `{os.path.basename(data.get('image_path', ''))}`\nSize: {data.get('file_size')} bytes"
                        
                    else:
                        final_content = f"**Success:**\n{json.dumps(data, indent=2)}"
                else:
                    msg = data.get('message') if isinstance(data, dict) else str(data)
                    final_content = f"**Processing Failed**: {msg}"

    except Exception as e:
        logger.error(f"Workflow failed: {str(e)}")
        final_content = f"System Error: {str(e)}"
        
    # --- Close the <think> block ---
    think_close = "\n</think>\n\n"
    yield StreamChunk(
        model=model,
        created_at=datetime.now().isoformat(),
        message=ChatMessage(role="assistant", content=think_close),
        done=False
    ).model_dump_json() + "\n"

    # 4. Stream the Final Response (Preserving Markdown Formatting)
    # We chunk by characters instead of splitting by words to preserve newlines (\n)
    
    chunk_size = 50  # Send 50 characters at a time
    for i in range(0, len(final_content), chunk_size):
        chunk = final_content[i:i+chunk_size]
        yield StreamChunk(
            model=model,
            created_at=datetime.now().isoformat(),
            message=ChatMessage(role="assistant", content=chunk),
            done=False
        ).model_dump_json() + "\n"
        await asyncio.sleep(0.01)
    
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


async def fetch_all_dags() -> List[Dict[str, Any]]:
    url = f"{AIRFLOW_HOST}/dags"
    async with httpx.AsyncClient(headers=AIRFLOW_HEADERS, timeout=10) as client:
        resp = await client.get(url)
    if resp.status_code != 200:
        logger.error(f"Failed to fetch DAGs: status {resp.status_code}")
        return []  # Graceful fallback to empty list
    return resp.json().get("dags", [])

def dag_to_model_entry(dag: Dict[str, Any]) -> Dict[str, Any]:
    description = dag.get("description", dag.get("dag_id"))
    return {
        "name": f"clipfoundry.ai {description}",  # Prefix for display
        "model": description,
        "modified_at": datetime.now().isoformat(),
        "size": 1024  # Fixed placeholder to match existing format
    }

@app.get("/api/tags")
async def list_models():
    dags = await fetch_all_dags()
    chat_ready = []
    for dag in dags:
        tags = dag.get("tags", [])
        is_chat_enabled = any(t.get("name") == "conversational" for t in tags)
        is_enabled = not dag.get("is_paused", True)  # Skip paused/disabled DAGs
        if is_chat_enabled and is_enabled:
            chat_ready.append(dag_to_model_entry(dag))
    return {"models": chat_ready}


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
        request_id = headers.get("x-openwebui-request-id", str(uuid.uuid4())[:8])
        
        logger.info(f"Chat request from user: {user_email} (ID: {user_id})")
        
        messages = body.get("messages", [])
        requested_model = body.get("model")
        if not requested_model:
            raise HTTPException(status_code=400, detail="Model (DAG description) is required")
        # Strip :latest if appended by client
        model = requested_model.rstrip(":latest")
        stream = body.get("stream", False)
        
        # Map model (description) to actual dag_id
        dags = await fetch_all_dags()
        matching_dag = next((d for d in dags if d.get("description") == model), None)
        if not matching_dag:
            raise HTTPException(status_code=400, detail=f"Model '{requested_model}' was not found")
        dag_id = matching_dag["dag_id"]
        user_role = headers.get('x-openwebui-user-role', 'user')
        vault_user = headers.get('x-ltai-vault-user', '')
        vault_keys = headers.get('x-ltai-vault-keys', '')
        
        if not messages:
            raise HTTPException(status_code=400, detail="Messages are required")
        
        last_message = messages[-1]
        user_content = last_message.get("content", "").strip()
        images = last_message.get("images", [])
        
        logger.info(f"Processing message with {len(images)} image(s), stream={stream}")
        
        response_parts = []
        saved_images = []
        saved_paths = []
        
        if images:
            response_parts.append(f"👤 Hello {user_name}! I received {len(images)} image(s).\n")
            
            for idx, base64_image in enumerate(images, 1):
                try:
                    image_bytes, metadata = verify_and_decode_image(base64_image)
                    save_info = save_image(image_bytes, request_id, metadata)
                    saved_images.append(save_info)
                    # Capture the absolute path for the DAG
                    saved_paths.append(save_info['path'])
                    
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
                f"   • Storage: `{SHARED_STORAGE_PATH}/{request_id}/`\n"
            )
        else:
            response_parts.append(
                f"👋 Hello {user_name}!\n\n"
                f"I'm the **Image Saver Assistant**. Send me images and I'll save them to shared storage.\n\n"
                f"📝 Your message: {user_content or 'No text, waiting for images...'}\n\n"
                f"💡 **How to use:** Attach images and send!"
            )
        
        response_content = "".join(response_parts)
        
        if stream and saved_paths:
            # TRIGGER DAG FLOW
            # We ignore the initial summary text for the stream and let the generator handle the response
            return StreamingResponse(
                generate_stream_response(model, saved_paths, user_content, dag_id, headers, messages, user_email, user_id, user_name, user_role, vault_user, vault_keys),
                media_type="application/x-ndjson"
            )
        elif stream and not saved_paths:
             # Fallback for text-only streaming
             return StreamingResponse(
                generate_stream_response(model, "", user_content, dag_id, headers, messages, user_email, user_id, user_name, user_role, vault_user, vault_keys), # Handle empty path case in generator if needed
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
