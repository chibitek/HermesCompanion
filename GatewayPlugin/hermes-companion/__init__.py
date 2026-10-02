"""Companion workspace routes, using Hermes's existing domain handlers.

Installed on the root API listener only. Named-profile routes are deliberately
not registered: a profile-scoped key must never acquire an all-profile roster.
"""

import asyncio
import inspect
import hashlib
import json
from pathlib import Path
import logging

log = logging.getLogger(__name__)


class WorkspaceRPCError(Exception):
    def __init__(self, method, code, message):
        self.method, self.code, self.message = method, code, message
        super().__init__(f"{method} ({code}): {message}")


def rpc(method, params):
    from tui_gateway.server import handle_request

    response = handle_request({"jsonrpc": "2.0", "id": 1, "method": method, "params": params})
    if isinstance(response, dict) and isinstance(response.get("error"), dict):
        error = response["error"]
        raise WorkspaceRPCError(method, error.get("code"), str(error.get("message") or "No error reason returned"))
    if not isinstance(response, dict) or "result" not in response:
        raise RuntimeError(f"Hermes workspace RPC {method} returned no result")
    return response["result"]


def bots(_query):
    return rpc("profiles.list", {"include_sessions": True})


async def bot_history(query):
    from hermes_cli.web_routers.sessions import get_session_messages

    profile = query.get("profile", "")
    offset = int(query.get("offset", "0"))
    if offset < 0:
        raise ValueError("offset must be nonnegative")
    roster = await asyncio.to_thread(rpc, "profiles.list", {"include_sessions": True})
    bot = next((p for p in roster["profiles"] if p["name"] == profile), None)
    if bot is None:
        raise ValueError("Select an existing Bot profile")
    # Resolve the canonical pointer on the server on every read, including after
    # compaction. Never accept a client's session pointer for a different Bot.
    session = bot.get("canonical_session")
    if not session:
        return {"profile": profile, "session_id": None, "messages": [],
                "pagination": {"offset": offset, "limit": 100, "returned": 0}}
    return await get_session_messages(session["id"], profile=profile, limit=100,
                                      offset=offset, order="latest", include_compacted=False)


def project_session_limit(profile):
    from hermes_cli.web_routers.sessions import _with_db

    # Count all rows (including archived/children) as an upper bound on the
    # native tree's filtered roots. Keep LIMIT positive even for an empty DB.
    count = _with_db(profile, lambda db: db.session_count(include_archived=True), read_only=True)
    if not isinstance(count, int) or isinstance(count, bool) or count < 0:
        raise RuntimeError("Hermes returned an invalid session count")
    return count + 1


def projects(_query):
    roster = rpc("profiles.list", {"include_sessions": False})
    groups, errors = [], []
    for profile in roster["profiles"]:
        name = profile["name"]
        try:
            tree = rpc("projects.tree", {"profile": name, "session_limit": project_session_limit(name)})
            groups.append({"profile": name, "projects": tree["projects"]})
        except Exception as exc:
            log.exception("Companion project tree unavailable for a profile")
            errors.append({"profile": name, "message": f"Project tree could not be loaded ({type(exc).__name__}). Check this profile's database and the gateway log."})
    return {"groups": groups, "errors": errors}


def project_detail(query):
    profile, project_id = query.get("profile", ""), query.get("project_id", "")
    names = {p["name"] for p in rpc("profiles.list", {"include_sessions": False})["profiles"]}
    if profile not in names or not project_id:
        raise ValueError("A valid profile and project_id are required")
    limit = project_session_limit(profile)
    detail = rpc("projects.project_sessions", {"profile": profile, "project_id": project_id,
                                                "session_limit": limit})
    if detail.get("project") is not None:
        return detail
    # Native drill-in skips the discovered-repository tier. Preserve an empty
    # folder from the authoritative overview, but never pass a preview off as
    # fully hydrated history for a project containing sessions.
    tree = rpc("projects.tree", {"profile": profile, "session_limit": limit})
    project = next((p for p in tree["projects"]
                    if p["id"] == project_id and p.get("sessionCount") == 0), None)
    return {**detail, "project": project}


def boards(_query):
    from plugins.kanban.dashboard.plugin_api import list_boards

    return list_boards(include_archived=False)


async def project_history(query):
    from hermes_cli.web_routers.sessions import get_session_messages

    offset = int(query.get("offset", "0"))
    session_id = query.get("session_id", "")
    if offset < 0 or not session_id:
        raise ValueError("A session and nonnegative offset are required")
    detail = await asyncio.to_thread(project_detail, query)
    project = detail.get("project") or {}
    sessions = {s["id"] for repo in project.get("repos", [])
                for group in repo.get("groups", []) for s in group.get("sessions", [])}
    if session_id not in sessions:
        raise ValueError("Session is not in the selected project")
    history = await get_session_messages(session_id, profile=query["profile"], limit=100,
                                         offset=offset, order="latest", include_compacted=False)
    return {"project_id": query["project_id"], "requested_session_id": session_id, "history": history}


def board(query):
    from plugins.kanban.dashboard.plugin_api import get_board, list_boards

    slug = query.get("board", "")
    if slug not in {b["slug"] for b in list_boards(include_archived=False)["boards"]}:
        raise ValueError("Select an existing board")
    return get_board(tenant=None, include_archived=False, board=slug,
                     workflow_template_id=None, current_step_key=None)


def task_detail(query):
    from plugins.kanban.dashboard.plugin_api import get_task, list_boards
    from fastapi import HTTPException

    slug, task_id = query.get("board", ""), query.get("task_id", "")
    if not task_id or slug not in {b["slug"] for b in list_boards(include_archived=False)["boards"]}:
        raise ValueError("Select an existing board and task")
    try:
        detail = get_task(task_id, board=slug, run_state_type=None, run_state_name=None)
    except HTTPException as exc:
        if exc.status_code == 404:
            raise ValueError("Task no longer exists on this board") from exc
        raise
    return {"board": slug, **detail}


def task_attachment(query):
    from aiohttp import web
    from plugins.kanban.dashboard.plugin_api import download_attachment

    attachment_id = int(query.get("attachment_id", "0"))
    detail = task_detail(query)
    if attachment_id <= 0 or not any(
        a["id"] == attachment_id and a["task_id"] == query["task_id"]
        for a in detail.get("attachments", [])
    ):
        raise ValueError("Attachment is not in the selected task")
    # Hermes validates the resolved path against this board's attachment root.
    native = download_attachment(attachment_id, board=query["board"])
    return web.FileResponse(native.path, headers={
        "Content-Type": native.media_type or "application/octet-stream",
        "Content-Disposition": native.headers["content-disposition"],
        "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff",
    })


def require_profile(query):
    name = query.get("profile", "")
    names = {p["name"] for p in rpc("profiles.list", {"include_sessions": False})["profiles"]}
    if name not in names:
        raise ValueError("Select an existing profile before managing projects")
    return name


def project_records(query):
    name = require_profile(query)
    return {"profile": name, **rpc("projects.list", {"profile": name})}


def project_record(query):
    name = require_profile(query)
    project_id = query.get("project_id", "")
    if not project_id:
        raise ValueError("A project_id is required")
    result = rpc("projects.get", {"profile": name, "id": project_id})
    if (result.get("project") or {}).get("id") != project_id:
        raise ValueError("Project identity no longer matches; refresh the project list")
    return {"profile": name, **result}


def project_mutation(query, payload, operation):
    name = require_profile(query)
    fields = {
        "create": {"name", "description", "slug", "folders", "primary_path", "icon", "color", "board_slug"},
        "update": {"name", "description", "icon", "color", "board_slug"},
        "add_folder": {"path", "label", "is_primary"},
        "remove_folder": {"path"}, "set_primary": {"path"},
        "archive": {"restore"}, "set_active": set(), "delete": set(),
    }[operation]
    if set(payload) - fields:
        raise ValueError("Unsupported project fields: " + ", ".join(sorted(set(payload) - fields)))
    for key, value in payload.items():
        if key == "folders":
            if not isinstance(value, list) or any(not isinstance(p, str) or not p.strip() for p in value):
                raise ValueError("folders must be a list of nonempty server paths")
        elif key in {"restore", "is_primary"}:
            if not isinstance(value, bool):
                raise ValueError(f"{key} must be true or false")
        elif not isinstance(value, str):
            raise ValueError(f"{key} must be text")
    if operation == "create" or "name" in payload:
        if not payload.get("name", "").strip():
            raise ValueError("A nonempty project name is required")
    if operation == "update" and not payload:
        raise ValueError("Choose a project field to change")
    if operation in {"add_folder", "remove_folder", "set_primary"} and not payload.get("path", "").strip():
        raise ValueError("A nonempty server folder path is required")
    # Native normalization treats a blank/relative path as gateway cwd. Require
    # explicit server paths so a phone edit cannot accidentally claim that cwd.
    for path in [*payload.get("folders", []), *([payload["path"]] if "path" in payload else []),
                 *([payload["primary_path"]] if payload.get("primary_path") else [])]:
        if not path.startswith(("/", "~/")):
            raise ValueError("Use an absolute server folder path or ~/ path")
    project_id = query.get("project_id", "")
    if operation != "create":
        if not project_id and operation != "set_active":
            raise ValueError("A project_id is required")
        if project_id:
            current = project_record(query)["project"]
            if operation == "delete" and rpc("projects.list", {"profile": name}).get("active_id") == project_id:
                raise ValueError("This project is active. Clear the active project in this profile before deleting its record")
            if operation in {"remove_folder", "set_primary"}:
                from hermes_cli.projects_db import _normalize_path
                if _normalize_path(payload["path"]) not in {f["path"] for f in current["folders"]}:
                    raise ValueError("Folder is no longer linked to this project; refresh before changing it")
    params = {"profile": name, **payload}
    if operation != "create":
        params["id"] = project_id
    result = rpc("projects." + operation, params)
    if operation in {"archive", "set_active", "delete"}:
        return {"profile": name, **rpc("projects.list", {"profile": name})}
    if not result.get("project") or (operation != "create" and result["project"].get("id") != project_id):
        raise RuntimeError("Hermes did not confirm the requested project")
    return {"profile": name, **result}


def create_project(query, payload):
    return project_mutation(query, payload, "create")


def update_project(query, payload):
    return project_mutation(query, payload, "update")


def add_project_folder(query, payload):
    return project_mutation(query, payload, "add_folder")


def remove_project_folder(query, payload):
    return project_mutation(query, payload, "remove_folder")


def primary_project_folder(query, payload):
    return project_mutation(query, payload, "set_primary")


def archive_project(query, payload):
    return project_mutation(query, payload, "archive")


def delete_project(query, payload):
    return project_mutation(query, payload, "delete")


def activate_project(query, payload):
    return project_mutation(query, payload, "set_active")


def workspace_capabilities(_query):
    from plugins.kanban.dashboard import plugin_api as native
    from hermes_cli.kanban_db import KANBAN_ATTACHMENT_MAX_BYTES

    return {"version": "0.1.11", "task_attachment_write": True, "task_link_write": True,
            "task_attachment_max_bytes": KANBAN_ATTACHMENT_MAX_BYTES, "task_attachment_chunk_bytes": 4 * 1024 * 1024, "board_manage": True, "project_manage": True, "task_create": True, "task_update": True,
            "task_comment": True, "task_statuses": [*native._STATUS_HANDLERS, "archived"]}


def require_board(query):
    slug = query.get("board", "")
    if not slug or slug not in {b["slug"] for b in boards({})["boards"]}:
        raise ValueError("Select an existing board before changing a task")
    return slug


def validated_payload(model, payload):
    unknown = set(payload) - set(model.model_fields)
    if unknown:
        raise ValueError("Unsupported task fields: " + ", ".join(sorted(unknown)))
    return model.model_validate(payload)


def create_board(query, payload):
    from plugins.kanban.dashboard import plugin_api as native
    from hermes_cli import kanban_db

    if query:
        raise ValueError("Board creation takes its slug from the request body")
    if "switch" in payload:
        raise ValueError("Select the active board with the separate board-active operation")
    body = validated_payload(native.CreateBoardBody, payload)
    slug = kanban_db._require_slug(body.slug)
    existing = next((b for b in boards({})["boards"] if b["slug"] == slug), None)
    # Native create_board writes display metadata even on slug reuse. A retry
    # must return the existing record without overwriting another client's edits.
    if existing is not None:
        return {"board": existing, "already_exists": True}
    result = native.create_board_endpoint(body)
    if result.get("board", {}).get("slug") != slug:
        raise RuntimeError("Hermes did not confirm the requested board")
    return {**result, "already_exists": False}


def update_board(query, payload):
    from plugins.kanban.dashboard import plugin_api as native

    slug = require_board(query)
    if not payload:
        raise ValueError("Choose at least one board field to change")
    result = native.rename_board(slug, validated_payload(native.RenameBoardBody, payload))
    if result.get("board", {}).get("slug") != slug:
        raise RuntimeError("Hermes did not confirm this board update")
    return result


def activate_board(query, payload):
    from plugins.kanban.dashboard import plugin_api as native

    if payload:
        raise ValueError("Active-board selection does not accept body fields")
    slug = require_board(query)
    result = native.switch_board(slug)
    if result.get("current") != slug:
        raise RuntimeError("Hermes did not confirm the active board")
    return {"slug": slug, "action": "activated", **result}


def archive_board(query, payload):
    from plugins.kanban.dashboard import plugin_api as native

    if payload:
        raise ValueError("Archiving does not accept delete or other body fields")
    slug = require_board(query)
    result = native.delete_board(slug, delete=False)
    receipt = result.get("result", {})
    if receipt.get("slug") != slug or receipt.get("action") != "archived":
        raise RuntimeError("Hermes did not confirm this board archive")
    return {"slug": slug, "action": "archived", "current": result["current"]}


def create_task(query, payload):
    from plugins.kanban.dashboard import plugin_api as native

    slug = require_board(query)
    if not isinstance(payload.get("title"), str) or not payload["title"].strip():
        raise ValueError("A task title is required")
    if not payload.get("idempotency_key"):
        raise ValueError("A stable idempotency_key is required to create a task safely")
    result = native.create_task(validated_payload(native.CreateTaskBody, payload), board=slug)
    if not result.get("task"):
        raise RuntimeError("Hermes did not return the created task")
    return {"board": slug, **result}


def update_task(query, payload):
    from plugins.kanban.dashboard import plugin_api as native

    slug = require_board(query)
    task_id = query.get("task_id", "")
    if not task_id:
        raise ValueError("A task_id is required")
    if not payload:
        raise ValueError("Choose at least one task field to change")
    if "title" in payload and (not isinstance(payload["title"], str) or not payload["title"].strip()):
        raise ValueError("The task title cannot be empty")
    status = payload.get("status")
    for field, statuses in {"result": {"done"}, "summary": {"done", "review"},
                            "block_reason": {"blocked", "scheduled"}}.items():
        if field in payload and status not in statuses:
            raise ValueError(f"{field} requires a transition to {' or '.join(sorted(statuses))}")
    # The native handler verifies membership and applies its workflow/worker
    # transition rules. Only fields explicitly sent by the editor are changed.
    result = native.update_task(task_id, validated_payload(native.UpdateTaskBody, payload), board=slug)
    if not result.get("task") or result["task"]["id"] != task_id:
        raise RuntimeError("Hermes did not confirm the requested task update")
    return {"board": slug, **result}


def comment_task(query, payload):
    from plugins.kanban.dashboard import plugin_api as native

    slug = require_board(query)
    task_id = query.get("task_id", "")
    if not task_id:
        raise ValueError("A task_id is required")
    if set(payload) != {"body"} or not isinstance(payload["body"], str):
        raise ValueError("Provide the comment body as text")
    # The author identifies the UI that submitted the comment; the client cannot
    # impersonate another profile or overwrite author attribution.
    result = native.add_comment(task_id, native.CommentBody(body=payload["body"], author="companion"), board=slug)
    return {"board": slug, "task_id": task_id, **result}



def attachment_context(query):
    slug = require_board(query)
    task_id = query.get("task_id", "")
    if not task_id:
        raise ValueError("Select a task before changing attachments")
    return slug, task_id, task_detail(query)


def delete_task_attachment(query, payload):
    from plugins.kanban.dashboard import plugin_api as native
    from fastapi import HTTPException
    slug, task_id, detail = attachment_context(query)
    if set(payload) != {"attachment_id"} or type(payload["attachment_id"]) is not int:
        raise ValueError("Provide one integer attachment_id")
    attachment_id = payload["attachment_id"]
    if not any(a["id"] == attachment_id and a["task_id"] == task_id for a in detail["attachments"]):
        raise HTTPException(404, "This attachment was removed or is not in the selected task. Refresh its attachment list.")
    native.remove_attachment(attachment_id, board=slug)
    return {"board": slug, "task_id": task_id, "attachment_id": attachment_id, "deleted": True}


def change_task_link(query, payload, linked):
    from plugins.kanban.dashboard import plugin_api as native
    slug = require_board(query)
    if set(payload) != {"parent_id", "child_id"} or not all(isinstance(v, str) and v for v in payload.values()):
        raise ValueError("Provide parent_id and child_id for this dependency")
    if query.get("task_id") not in payload.values():
        raise ValueError("The selected task must be one end of the dependency")
    for task_id in payload.values():
        task_detail({"board": slug, "task_id": task_id})
    if linked:
        native.add_link(native.LinkBody(**payload), board=slug)
    else:
        native.delete_link(board=slug, **payload)
    current = task_detail({"board": slug, "task_id": payload["parent_id"]})
    if (payload["child_id"] in current["links"]["children"]) != linked:
        raise RuntimeError("Hermes did not confirm the requested dependency state")
    return {"board": slug, **payload, "linked": linked}


def add_task_link(query, payload):
    return change_task_link(query, payload, True)


def remove_task_link(query, payload):
    return change_task_link(query, payload, False)


def upload_state(query, payload):
    import contextlib, fcntl, uuid
    from hermes_constants import get_hermes_home
    attachment_context(query)
    upload_id = payload.get("upload_id", "")
    try:
        valid_id = isinstance(upload_id, str) and str(uuid.UUID(upload_id)) == upload_id
    except ValueError:
        valid_id = False
    if not valid_id:
        raise ValueError("A stable lowercase UUID upload_id is required")
    # The hash binds state and locks to one board/task/operation, never a client path.
    owner = hashlib.sha256(json.dumps([query["board"], query["task_id"], upload_id]).encode()).hexdigest()
    directory = Path(get_hermes_home()) / ".companion" / "uploads" / owner
    directory.mkdir(parents=True, exist_ok=True)
    @contextlib.contextmanager
    def locked():
        with (directory / "lock").open("a+b") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            yield directory
    return locked()


def save_upload_state(directory, state):
    import os
    temporary = directory / "state.next"
    with temporary.open("w") as file:
        json.dump(state, file)
        file.flush()
        os.fsync(file.fileno())
    temporary.replace(directory / "state.json")


def upload_receipt(query, state, offset):
    return {"board": query["board"], "task_id": query["task_id"],
            "upload_id": state["upload_id"], "offset": offset,
            "attachment": state.get("attachment")}



_upload_cleanup_after = 0.0


def expire_upload_staging(root):
    import fcntl, time
    global _upload_cleanup_after
    now = time.time()
    if now < _upload_cleanup_after:
        return
    _upload_cleanup_after = now + 3600
    for directory in root.iterdir():
        try:
            with (directory / "lock").open("a+b") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                files = [p for p in (directory / "state.json", directory / "content") if p.exists()]
                if files and max(p.stat().st_mtime for p in files) < now - 7 * 86400:
                    for path in files:
                        path.unlink(missing_ok=True)
        except (BlockingIOError, OSError):
            continue



def require_not_removed_upload(query, upload_id):
    from fastapi import HTTPException
    detail = task_detail(query)
    marker = "companion-upload:" + upload_id
    if any(a.get("uploaded_by") == marker for a in detail["attachments"]):
        return
    for event in detail.get("events", []):
        if event.get("kind") != "attached":
            continue
        payload = event.get("payload") or {}
        if isinstance(payload, str):
            try:
                payload = json.loads(payload)
            except ValueError:
                continue
        if isinstance(payload, dict) and payload.get("by") == marker:
            raise HTTPException(409, "This completed attachment was removed. Start a new upload only if you intend to restore it.")


def begin_task_upload(query, payload):
    import re
    from hermes_cli.kanban_db import KANBAN_ATTACHMENT_MAX_BYTES, _safe_attachment_name
    from fastapi import HTTPException
    fields = {"upload_id", "filename", "content_type", "size", "sha256"}
    if set(payload) != fields:
        raise ValueError("Upload metadata requires upload_id, filename, content_type, size and sha256")
    if type(payload["size"]) is not int or not 0 <= payload["size"] <= KANBAN_ATTACHMENT_MAX_BYTES:
        raise HTTPException(413, f"Task attachments must be at most {KANBAN_ATTACHMENT_MAX_BYTES} bytes")
    if not isinstance(payload["sha256"], str) or not re.fullmatch(r"[a-f0-9]{64}", payload["sha256"]):
        raise ValueError("Provide the lowercase SHA-256 of the complete file")
    if not isinstance(payload["content_type"], str) or len(payload["content_type"]) > 200 or any(c in payload["content_type"] for c in "\r\n"):
        raise ValueError("The attachment content type is invalid")
    if not isinstance(payload["filename"], str):
        raise ValueError("The attachment filename must be text")
    metadata = {**payload, "filename": _safe_attachment_name(payload["filename"])}
    with upload_state(query, payload) as directory:
        expire_upload_staging(directory.parent)
        require_not_removed_upload(query, payload["upload_id"])
        state_path = directory / "state.json"
        if state_path.exists():
            state = json.loads(state_path.read_text())
            if any(state.get(key) != metadata[key] for key in fields):
                raise HTTPException(409, "This upload ID belongs to a different file. Keep the original file when retrying.")
        else:
            state = metadata
            save_upload_state(directory, state)
        offset = state["size"] if state.get("attachment") else ((directory / "content").stat().st_size if (directory / "content").exists() else 0)
        return upload_receipt(query, state, offset)


def append_task_upload(query, payload):
    import base64, binascii, os
    from fastapi import HTTPException
    if set(payload) != {"upload_id", "offset", "data"} or type(payload["offset"]) is not int or not isinstance(payload["data"], str):
        raise ValueError("Upload chunks require upload_id, integer offset and base64 data")
    if len(payload["data"]) > 5_592_408:
        raise HTTPException(413, "Each attachment chunk must be at most 4 MiB")
    try:
        data = base64.b64decode(payload["data"], validate=True)
    except (ValueError, binascii.Error) as exc:
        raise ValueError("The attachment chunk is not valid base64") from exc
    if not data or len(data) > 4 * 1024 * 1024 or payload["offset"] < 0:
        raise ValueError("Send a nonempty chunk of at most 4 MiB at a nonnegative offset")
    with upload_state(query, payload) as directory:
        if not (directory / "state.json").exists():
            raise HTTPException(409, "Start this upload before sending file chunks")
        state = json.loads((directory / "state.json").read_text())
        if state.get("attachment"):
            return upload_receipt(query, state, state["size"])
        path = directory / "content"
        current = path.stat().st_size if path.exists() else 0
        offset = payload["offset"]
        if offset + len(data) > state["size"] or offset > current:
            raise HTTPException(409, f"Upload expects offset {current}; refresh the upload before resuming")
        if offset < current:
            with path.open("rb") as file:
                file.seek(offset)
                if file.read(len(data)) != data:
                    raise HTTPException(409, "Retried chunk differs from the bytes already saved")
        else:
            with path.open("ab") as file:
                file.write(data)
                file.flush()
                os.fsync(file.fileno())
            current += len(data)
        return upload_receipt(query, state, current)


def finish_task_upload(query, payload):
    from plugins.kanban.dashboard import plugin_api as native
    from fastapi import HTTPException
    from starlette.datastructures import UploadFile, Headers
    if set(payload) != {"upload_id"}:
        raise ValueError("Finish requires only the original upload_id")
    with upload_state(query, payload) as directory:
        if not (directory / "state.json").exists():
            raise HTTPException(409, "Start this upload before completing it")
        state = json.loads((directory / "state.json").read_text())
        slug, task_id, detail = attachment_context(query)
        require_not_removed_upload(query, state["upload_id"])
        marker = "companion-upload:" + state["upload_id"]
        existing = [a for a in detail["attachments"] if a.get("uploaded_by") == marker]
        if len(existing) > 1:
            raise HTTPException(409, "Hermes found multiple receipts for this upload. Refresh attachments before retrying.")
        if state.get("attachment") or existing:
            if not existing:
                raise HTTPException(409, "This completed attachment was removed. Start a new upload only if you intend to restore it.")
            attachment = existing[0]
            native_file = native.download_attachment(attachment["id"], board=slug)
            if attachment["size"] != state["size"] or hashlib.sha256(Path(native_file.path).read_bytes()).hexdigest() != state["sha256"]:
                raise HTTPException(409, "The saved upload receipt does not match this file. Refresh attachments before retrying.")
        else:
            content = directory / "content"
            if state["size"] == 0:
                content.touch(exist_ok=True)
            if not content.exists() or content.stat().st_size != state["size"]:
                raise HTTPException(409, "The attachment is incomplete. Resume the upload before finishing.")
            if hashlib.sha256(content.read_bytes()).hexdigest() != state["sha256"]:
                raise HTTPException(422, "The uploaded bytes do not match the original file checksum. Select the original file and start a new upload.")
            async def upload():
                with content.open("rb") as file:
                    incoming = UploadFile(file, filename=state["filename"], headers=Headers({"content-type": state["content_type"]}))
                    return await native.upload_task_attachment(task_id, file=incoming, board=slug, uploaded_by=marker)
            attachment = asyncio.run(upload())["attachment"]
        state["attachment"] = {k: attachment[k] for k in ("id", "task_id", "filename", "content_type", "size")}
        save_upload_state(directory, state)
        (directory / "content").unlink(missing_ok=True)
        return upload_receipt(query, state, state["size"])


WRITERS = {
    ("POST", "task-upload-begin"): begin_task_upload,
    ("POST", "task-upload-chunk"): append_task_upload,
    ("POST", "task-upload-finish"): finish_task_upload,
    ("DELETE", "task-attachment"): delete_task_attachment,
    ("POST", "task-link"): add_task_link,
    ("DELETE", "task-link"): remove_task_link,
    ("POST", "boards"): create_board,
    ("PATCH", "board"): update_board,
    ("POST", "board-active"): activate_board,
    ("POST", "board-archive"): archive_board,
    ("POST", "projects-create"): create_project,
    ("PATCH", "project-record"): update_project,
    ("DELETE", "project-record"): delete_project,
    ("POST", "project-folder"): add_project_folder,
    ("DELETE", "project-folder"): remove_project_folder,
    ("POST", "project-primary"): primary_project_folder,
    ("POST", "project-archive"): archive_project,
    ("POST", "project-active"): activate_project,
    ("POST", "tasks"): create_task,
    ("PATCH", "task"): update_task,
    ("POST", "task-comment"): comment_task,
}


READERS = {
    "project-records": project_records,
    "project-record": project_record,
    "capabilities": workspace_capabilities,
    "projects": projects,
    "project": project_detail,
    "project-history": project_history,
    "bots": bots,
    "bot-history": bot_history,
    "boards": boards,
    "board": board,
    "task": task_detail,
    "task-attachment": task_attachment,
}


def change_fingerprint():
    """Cheap invalidation token from server-owned paths, never file contents.

    SQLite WAL changes cover writes from other Hermes processes. This is an
    invalidation hint; normal domain reads remain the source of truth.
    """
    from hermes_cli.profiles import get_profile_dir, list_profile_names
    from hermes_cli import kanban_db

    paths = []
    for profile in list_profile_names():
        home = get_profile_dir(profile)
        for name in ("state.db", "projects.db", "config.yaml", "cron/jobs.json"):
            path = home / name
            paths.append(path)
            if name.endswith(".db"):
                paths.append(Path(str(path) + "-wal"))
    for board in kanban_db.list_boards(include_archived=True):
        path = kanban_db.kanban_db_path(board=board["slug"])
        paths.extend((path, Path(str(path) + "-wal"), kanban_db.board_metadata_path(board["slug"])))
    return fingerprint_paths(paths)


def fingerprint_paths(paths):
    records = []
    for path in sorted(set(paths)):
        try:
            stat = path.stat()
            records.append((str(path), stat.st_ino, stat.st_size, stat.st_mtime_ns))
        except FileNotFoundError:
            records.append((str(path), None))
    return hashlib.sha256(json.dumps(records).encode()).hexdigest()


async def stream_changes(request, adapter):
    from aiohttp import web

    denied = adapter._check_auth(request)
    if denied is not None:
        return denied
    try:
        previous = await asyncio.to_thread(change_fingerprint)
    except Exception as exc:
        log.exception("Companion change monitor initialization failed")
        return web.json_response({"error": {
            "code": "companion_change_monitor_unavailable",
            "message": f"Cannot monitor Hermes workspace changes ({type(exc).__name__}). Check the gateway log and bridge compatibility."
        }}, status=503)
    response = web.StreamResponse(headers={
        "Content-Type": "text/event-stream", "Cache-Control": "no-store",
        "X-Accel-Buffering": "no",
    })
    await response.prepare(request)

    async def changed(revision):
        payload = json.dumps({"delta": revision})
        await response.write(f"event: workspace.changed\ndata: {payload}\n\n".encode())

    try:
        await changed(previous)
        ticks = 0
        while True:
            await asyncio.sleep(1)
            current = await asyncio.to_thread(change_fingerprint)
            if current != previous:
                previous = current
                await changed(current)
            ticks += 1
            if ticks % 5 == 0:
                await response.write(b": keepalive\n\n")
    except (ConnectionResetError, BrokenPipeError, asyncio.CancelledError):
        pass
    except Exception as exc:
        log.exception("Companion change monitor stopped")
        payload = json.dumps({"message": f"Workspace change monitoring stopped ({type(exc).__name__}). Check the gateway log; Companion will reconnect."})
        try:
            await response.write(f"event: error\ndata: {payload}\n\n".encode())
        except (ConnectionError, OSError):
            pass
    return response


def wire(app, adapter):
    from aiohttp import web

    def handler(reader):
        async def read(request):
            # Use the gateway's existing authorization decision unchanged.
            denied = adapter._check_auth(request)
            if denied is not None:
                return denied
            try:
                result = await asyncio.to_thread(reader, dict(request.query))
                if inspect.isawaitable(result):
                    result = await result
                if isinstance(result, web.StreamResponse):
                    return result
                return web.json_response(result, headers={"Cache-Control": "no-store"})
            except WorkspaceRPCError as exc:
                status = 404 if exc.code == 5062 else 400 if exc.code == 5063 else 503
                return web.json_response({"error": {"code": str(exc.code), "message": str(exc)}}, status=status)
            except ValueError as exc:
                return web.json_response({"error": str(exc)}, status=400)
            except Exception as exc:
                log.exception("Companion workspace read failed: %s", reader.__name__)
                return web.json_response({"error": {
                    "code": "companion_" + reader.__name__ + "_failed",
                    "message": f"Hermes could not load {reader.__name__.replace('_', ' ')} ({type(exc).__name__}). Check the gateway log and Companion bridge version."
                }}, status=503)
        return read

    def write_handler(writer):
        async def write(request):
            denied = adapter._check_auth(request)
            if denied is not None:
                return denied
            from fastapi import HTTPException
            from pydantic import ValidationError
            try:
                payload = await request.json()
                if not isinstance(payload, dict):
                    raise ValueError("The workspace request must be a JSON object")
                query = dict(request.query)
                allowed_query = ({"profile", "project_id"} if "project" in writer.__name__
                                 else {"board"} if writer.__name__.endswith("_board") else {"board", "task_id"})
                if set(query) - allowed_query:
                    raise ValueError("Only " + ", ".join(sorted(allowed_query)) + " query fields are accepted")
                result = await asyncio.to_thread(writer, query, payload)
                return web.json_response(result, headers={"Cache-Control": "no-store"})
            except ValidationError as exc:
                details = "; ".join(".".join(map(str, item["loc"])) + ": " + item["msg"] for item in exc.errors())
                return web.json_response({"error": {"code": "invalid_workspace_fields", "message": details}}, status=422)
            except HTTPException as exc:
                return web.json_response({"error": {"code": "workspace_operation_rejected", "message": str(exc.detail)}}, status=exc.status_code)
            except WorkspaceRPCError as exc:
                status = 404 if exc.code == 5062 else 400 if exc.code == 5063 else 503
                return web.json_response({"error": {"code": str(exc.code), "message": str(exc)}}, status=status)
            except ValueError as exc:
                return web.json_response({"error": str(exc)}, status=400)
            except Exception as exc:
                log.exception("Companion workspace mutation failed: %s", writer.__name__)
                return web.json_response({"error": {
                    "code": "companion_" + writer.__name__ + "_failed",
                    "message": f"Hermes could not confirm {writer.__name__.replace('_', ' ')} ({type(exc).__name__}). Refresh this resource before retrying; part of the change may already have been applied."
                }}, status=503)
        return write

    for (method, path), writer in WRITERS.items():
        app.router.add_route(method, "/api/companion/" + path, write_handler(writer))

    app.router.add_get("/api/companion/changes", lambda request: stream_changes(request, adapter))

    for path, reader in READERS.items():
        app.router.add_get("/api/companion/" + path, handler(reader))


def register(ctx):
    ctx.register_platform_handler("api_server", wire)
