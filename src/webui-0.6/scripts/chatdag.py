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
from fastapi.staticfiles import StaticFiles
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
CACHE_ROOT = os.getenv("CACHE_DIR")
LOGS_ROOT = os.getenv("LOGS_DIR")
MAX_FILE_SIZE = 10 * 1024 * 1024  # 10MB
ALLOWED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp"}

# Ensure storage directory exists
Path(SHARED_STORAGE_PATH).mkdir(parents=True, exist_ok=True)
Path(VIDEO_OUTPUT_DIR).mkdir(parents=True, exist_ok=True)
Path(CACHE_ROOT).mkdir(parents=True, exist_ok=True)
Path(LOGS_ROOT).mkdir(parents=True, exist_ok=True)
logger.info(f"Image storage path: {SHARED_STORAGE_PATH}")
logger.info(f"Video output path: {VIDEO_OUTPUT_DIR}")
logger.info(f"Cache path: {CACHE_ROOT}")
logger.info(f"Logs path: {LOGS_ROOT}")

if os.path.exists(VIDEO_OUTPUT_DIR):
    app.mount("/static/videos", StaticFiles(directory=VIDEO_OUTPUT_DIR), name="video_static")

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
        source = Path(source_video_path)
        
        if not source.exists():
            clean_rel = str(source).lstrip("/") 
            source = Path(SHARED_STORAGE_PATH) / clean_rel
            
        if not source.exists():
            logger.error(f"File not found. Checked: {source_video_path} AND {source}")
            raise ValueError(f"Source video not found at: {source_video_path}")
        
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        unique_id = str(uuid.uuid4())[:8]
        filename = f"video_{timestamp}_{unique_id}.mp4"  # Assuming MP4; adjust if needed
        
        target_path = Path(VIDEO_OUTPUT_DIR) / filename
        logger.info(f"Copying video: {source} -> {target_path}")
        shutil.copy2(source, target_path)
        
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


def save_image(image_bytes: bytes, destination_dir: Path, metadata: dict) -> dict:
    """Save image to specific directory."""
    try:
        format_to_ext = {
            "JPEG": ".jpg", "PNG": ".png", "GIF": ".gif",
            "BMP": ".bmp", "WEBP": ".webp"
        }
        file_ext = format_to_ext.get(metadata.get("format", "PNG"), ".png")
        
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        unique_id = str(uuid.uuid4())[:8]
        filename = f"img_{timestamp}_{unique_id}{file_ext}"
        
        file_path = destination_dir / filename
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


def map_log_to_friendly_status(line: str, is_internal: bool = False) -> Optional[str]:
    """
    Filters logs:
    - Always returns messages with 'Thinking:'.
    - If is_internal is True, returns filtered debug logs (no italics).
    """
    line = line.strip()
    if not line:
        return None
    
    # 1. Always show Thinking logs (High Priority)
    TOKEN = "Thinking:"
    if TOKEN in line:
        # Split on the token and return everything after it
        return line.split(TOKEN, 1)[1].strip()

    # 2. Filter logic for Internal Users
    if is_internal:
        # Aggressive blacklist for Airflow system noise
        IGNORE_PATTERNS = [
            "Error fetching the logs", "default_host",
            "::group::", "::endgroup::",
            "AIRFLOW_CTX_", "Exporting env vars",
            "Pre task execution logs", "Post task execution logs",
            "Dependencies all met", "Starting attempt",
            "Executing <Task", "Started process",
            "Running: ['", "Subtask",
            "Running <TaskInstance", "Task exited with return code",
            "Marking task as SUCCESS", "downstream tasks scheduled",
            "Following branch", "Branch into",
            "Skipping tasks", "cannot be called outside TaskInstance",
            "Returned value was", "***"
        ]
        
        # If line contains any ignored pattern, skip it
        if any(pattern in line for pattern in IGNORE_PATTERNS):
            return None
            
        # Return clean log line
        return line
    return None

def get_airflow_logs(run_id: str, try_number: int, dag_id: str, task_id: str, map_index: int = -1) -> list:
    """Fetches and cleans logs for the specific task run."""
    url = f"{AIRFLOW_HOST}/dags/{dag_id}/dagRuns/{run_id}/taskInstances/{task_id}/logs/{try_number}?map_index={map_index}"
    try:
        res = requests.get(url, headers=AIRFLOW_HEADERS, timeout=5)
        if res.status_code == 200:
            return res.content.decode('utf-8', errors='replace').split('\n')
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

async def get_task_docs(dag_id: str) -> Dict[str, str]:
    """Fetches task definitions to map task_ids to doc_md (friendly names)."""
    url = f"{AIRFLOW_HOST}/dags/{dag_id}/tasks"
    try:
        async with httpx.AsyncClient(headers=AIRFLOW_HEADERS, timeout=5) as client:
            resp = await client.get(url)
            if resp.status_code == 200:
                tasks = resp.json().get("tasks", [])
                return {t["task_id"]: t.get("doc_md") for t in tasks}
    except Exception as e:
        logger.warning(f"Could not fetch task docs: {e}")
    return {}

async def generate_stream_response(model: str, image_paths: List[str], original_prompt: str, dag_id: str, headers: Dict[str, str], messages: List[Dict[str, Any]], user_email: str, user_id: str, user_name: str, user_role: str, vault_user: str, vault_keys: str, chat_id: str) -> AsyncGenerator[str, None]:
    """Streaming response with Airflow logs inside a <think> block."""
    
    request_id = headers.get("x-openwebui-request-id", str(uuid.uuid4()))
    is_internal = "ecloudcontrol.com" in user_email or user_role == "admin"
    task_docs = await get_task_docs(dag_id)
    
    # Initialize variables at the start to avoid UnboundLocalError
    is_rich_media = False
    final_content = "Processing..."
    video_url = None
    
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
            "X-LTAI-Request-ID": request_id,
            "X-LTAI-Chat-ID": chat_id
        }
        # Construct chat_inputs (adapt to existing structure)
        last_message = messages[-1] if messages else {}
        # Map all paths to the file object structure
        files_list = [{"path": p, "type": "image"} for p in image_paths]
        raw_history = messages[:-1] if len(messages) > 1 else []
        filtered_history = []

        for msg in raw_history:
            content = msg.get("content", "")
            # Check if this is a previous Assistant response containing the generated video/HTML
            if msg.get("role") == "assistant" and ("### 🎬 Video Ready!" in content or "<video" in content):
                sanitized_msg = msg.copy()
                sanitized_msg["content"] = "✅ [Video successfully generated and delivered to user]"
                # Remove images from assistant reply if any exist to save tokens
                if "images" in sanitized_msg:
                    sanitized_msg["images"] = [] 
                filtered_history.append(sanitized_msg)
            else:
                # Keep User messages (with their images/prompts) and text-only Assistant replies intact
                filtered_history.append(msg)

        chat_inputs = {
            "message": last_message.get("content", ""),
            "history": filtered_history,
            "files": files_list,
            "args": {"image_path": image_paths[0]} if image_paths else {},  # Preserve for DAG compatibility
            "timestamp": datetime.utcnow().isoformat(),
            "chat_id": chat_id
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

        # Get initial task instances
        ti_url = f"{AIRFLOW_HOST}/dags/{dag_id}/dagRuns/{dag_run_id}/taskInstances"
        ti_resp = requests.get(ti_url, headers=AIRFLOW_HEADERS)
        task_instances = ti_resp.json().get("task_instances", []) if ti_resp.status_code == 200 else []

        # Helper: Robust Key Generation
        def get_ti_key(ti):
            raw_idx = ti.get('map_index')
            idx = -1 if raw_idx is None else raw_idx
            return f"{ti['task_id']}_{idx}"

        last_log_counts = {}
        started_tasks = set()     # Tracks 'Started {task}'
        completed_tasks = set()   # Tracks 'Completed {task}'
        last_success_task = None

        status = "running"
        while status in ["queued", "running"]:
            await asyncio.sleep(2) # Polling interval

            # Refresh run state
            run_resp = requests.get(f"{AIRFLOW_HOST}/dags/{dag_id}/dagRuns/{dag_run_id}", headers=AIRFLOW_HEADERS)
            if run_resp.status_code == 200:
                status = run_resp.json().get("state", "running")

            # Refresh task list
            ti_resp = requests.get(ti_url, headers=AIRFLOW_HEADERS)
            if ti_resp.status_code != 200:
                continue
                
            task_instances = ti_resp.json().get("task_instances", [])

            # Tasks are processed in chronological order of their start time
            task_instances.sort(key=lambda x: x.get('start_date') or "9999-12-31")

            # Poll each task
            for ti in task_instances:
                task_id = ti["task_id"]
                current_state = ti.get("state")
                
                # If the task is skipped, ignore it completely (no start, no logs, no complete)
                if current_state == "skipped":
                    continue
                
                # Normalize map_index
                raw_idx = ti.get('map_index')
                map_index = -1 if raw_idx is None else raw_idx
                
                unique_key = get_ti_key(ti)
                try_num = ti.get("try_number", 1)

                # Initialize log count if new task found
                if unique_key not in last_log_counts:
                    last_log_counts[unique_key] = 0

                # 1. Emit "Started"
                is_active = current_state in ["running", "queued", "upstream_failed"]
                is_done = current_state in ["success", "failed"]
                if (is_active or is_done) and unique_key not in started_tasks:
                    friendly_name = task_docs.get(task_id) or task_id
                    
                    # Show technical ID only to internal users
                    display_name = f"{friendly_name} (`{task_id}`)" if is_internal else friendly_name
                    # Add map index to display if it's a parallel task
                    if map_index >= 0:
                        display_name += f" #{map_index + 1}"
                    yield StreamChunk(
                        model=model,
                        created_at=datetime.now().isoformat(),
                        message=ChatMessage(role="assistant", content=f"**{display_name}**...\n"),
                        done=False
                    ).model_dump_json() + "\n"
                    started_tasks.add(unique_key)

                # 2. Stream Logs
                # Only fetch logs if the task is active or finished
                if unique_key in started_tasks:
                    if current_state not in ["queued", "scheduled", "None"]:
                        logs = get_airflow_logs(dag_run_id, try_num, dag_id, task_id, map_index=map_index)
                        current_count = last_log_counts.get(unique_key, 0)
                        new_logs = logs[current_count:]
                        last_log_counts[unique_key] = len(logs)

                        for line in new_logs:
                            clean = map_log_to_friendly_status(line, is_internal=is_internal)
                            if clean:
                                yield StreamChunk(
                                    model=model,
                                    created_at=datetime.now().isoformat(),
                                    message=ChatMessage(role="assistant", content=f"{clean}\n"),
                                    done=False
                                ).model_dump_json() + "\n"

                # 3. Emit "Completed"
                if is_done and unique_key not in completed_tasks:
                    friendly_name = task_docs.get(task_id) or task_id

                    # Show technical ID only to internal users
                    display_name = f"{friendly_name} (`{task_id}`)" if is_internal else friendly_name
                    if map_index >= 0:
                        display_name += f" #{map_index + 1}"
                    yield StreamChunk(
                        model=model,
                        created_at=datetime.now().isoformat(),
                        message=ChatMessage(role="assistant", content=f"Completed **{display_name}**\n"),
                        done=False
                    ).model_dump_json() + "\n"
                    completed_tasks.add(unique_key)
                    if current_state == "success":
                        last_success_task = task_id
        
            # Refresh task list for next iteration
            ti_resp = requests.get(ti_url, headers=AIRFLOW_HEADERS)
            if ti_resp.status_code == 200:
                task_instances = ti_resp.json().get("task_instances", [])

        # Final Poll to ensure we catch the very last task state if loop exited fast
        ti_resp = requests.get(ti_url, headers=AIRFLOW_HEADERS)
        if ti_resp.status_code == 200:
            task_instances = ti_resp.json().get("task_instances", [])
            # Sort by end_date to find the true last successful task
            successful_tasks = [
                ti for ti in task_instances 
                if ti.get('state') == 'success' and ti.get('end_date') and ti['task_id'] != 'end'
            ]
            if successful_tasks:
                # Sort by end_date descending to get the absolute last one
                successful_tasks.sort(key=lambda x: x['end_date'], reverse=True)
                last_success_task = successful_tasks[0]['task_id']
                logger.info(f"Final poll identified last successful task: {last_success_task}")

        # Final XCom Retrieval
        final_content = "DAG completed but no result found."
        if last_success_task:
            xcom_url = f"{AIRFLOW_HOST}/dags/{dag_id}/dagRuns/{dag_run_id}/taskInstances/{last_success_task}/xcomEntries/return_value"
            xcom_resp = requests.get(xcom_url, headers=AIRFLOW_HEADERS)
            if xcom_resp.status_code == 200:
                raw = xcom_resp.json().get("value")
                data = None
                if isinstance(raw, (dict, list)):
                    data = raw
                elif isinstance(raw, str):
                    try:
                        data = json.loads(raw)
                    except json.JSONDecodeError:
                        try:
                            data = ast.literal_eval(raw)
                        except (ValueError, SyntaxError):
                            data = {"message": raw, "status": "unknown"}
                
                if isinstance(data, dict) and data.get("status") == "success":
                    
                    if "markdown_output" in data:
                        final_content = data["markdown_output"]
                    
                    elif "video_path" in data:
                        vid_path = data["video_path"]
                        video_url = save_video_to_static_dir(vid_path)
                        
                        final_content = (
                            f"### 🎬 Video Ready!\n\n"
                            f"Your video has been generated successfully.\n\n"
                            f"[**⬇️ Click here to Download**]({video_url})"
                        )
                    
                        is_rich_media = True
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

    # Stream the Final Response
    if is_rich_media and video_url:
        # IMPORTANT: Send rich HTML in one atomic message
        yield StreamChunk(
            model=model,
            created_at=datetime.now().isoformat(),
            message=ChatMessage(
                role="assistant",
                content=final_content,
                files=[
                    {
                        "type": "video",
                        "url": video_url,
                        "name": os.path.basename(video_url)
                    }
                ]
            ),
            done=False
        ).model_dump_json() + "\n"
    else:
        # Safe to stream text / markdown
        chunk_size = 50
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
        
        chat_id = headers.get('x-openwebui-chat-id', request_id)
        logging.info(f"Chat ID: {chat_id}")
        
        chat_shared_path = Path(SHARED_STORAGE_PATH) / chat_id
        chat_cache_path = Path(CACHE_ROOT) / chat_id
        chat_logs_path = Path(LOGS_ROOT) / chat_id
        
        for p in [chat_shared_path, chat_cache_path, chat_logs_path]:
            p.mkdir(parents=True, exist_ok=True)
        
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
        
        # Collect EXISTING images from chat directory FIRST
        existing_paths = []
        for file_path in chat_shared_path.iterdir():
            if file_path.suffix.lower() in ALLOWED_EXTENSIONS:
                existing_paths.append(str(file_path))
        
        logger.info(f"Found {len(existing_paths)} existing images in chat directory")
        
        # Check if current message has NEW images
        has_new_images = images and isinstance(images, list) and len(images) > 0
        
        if not has_new_images:
            logger.info("No new images in current message, checking conversation history...")
            # Don't pull from history - we already have existing_paths
            # Only log what we found
            logger.info(f"Will use {len(existing_paths)} existing images from chat directory")
        
        logger.info(f"Processing message with {len(images)} NEW image(s), {len(existing_paths)} existing, stream={stream}")
        
        response_parts = []
        saved_images = []
        newly_saved_paths = []
        
        # Only process and save NEW images from current message
        if has_new_images:
            response_parts.append(
                f"👤 Hello {user_name}! I received {len(images)} new image(s). "
                f"There are already {len(existing_paths)} images in this chat.\n"
            )
            
            for idx, base64_image in enumerate(images, 1):
                try:
                    image_bytes, metadata = verify_and_decode_image(base64_image)
                    save_info = save_image(image_bytes, chat_shared_path, metadata)
                    saved_images.append(save_info)
                    # Store the absolute path for newly saved images
                    newly_saved_paths.append(save_info['path'])
                    
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
                f"   • New images saved: {len(saved_images)}/{len(images)}\n"
                f"   • Total size (new): {total_size / 1024:.2f} KB\n"
                f"   • Storage: `{SHARED_STORAGE_PATH}/{chat_id}/`\n"
            )
        else:
            # No new images uploaded
            if existing_paths:
                response_parts.append(
                    f"👋 Hello {user_name}!\n\n"
                    f"📝 Your message: {user_content or 'Processing request...'}\n\n"
                    f"📂 Using {len(existing_paths)} existing image(s) from this chat.\n"
                )
            else:
                response_parts.append(
                    f"👋 Hello {user_name}!\n\n"
                    f"I'm the **Image Saver Assistant**. Send me images and I'll save them to shared storage.\n\n"
                    f"📝 Your message: {user_content or 'No text, waiting for images...'}\n\n"
                    f"💡 **How to use:** Attach images and send!\n\n"
                    f"📂 **Existing images in chat:** {len(existing_paths)} available."
                )
        
        # Combine existing + newly saved paths for DAG processing
        all_image_paths = existing_paths + newly_saved_paths
        
        response_parts.append(f"\n🔗 **Total images available for processing:** {len(all_image_paths)}")
        
        logger.info(f"Passing {len(all_image_paths)} images to DAG: {len(existing_paths)} existing + {len(newly_saved_paths)} new")
        
        response_content = "".join(response_parts)
        
        if stream:
            # Pass all available images to the streaming response
            return StreamingResponse(
                generate_stream_response(
                    model, all_image_paths, user_content, dag_id, headers, 
                    messages, user_email, user_id, user_name, user_role, 
                    vault_user, vault_keys, chat_id
                ),
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