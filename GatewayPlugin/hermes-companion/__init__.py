"""Read-only Companion routes, using Hermes's existing domain handlers.

Installed on the root API listener only. Named-profile routes are deliberately
not registered: a profile-scoped key must never acquire an all-profile roster.
"""

import asyncio
import inspect
import logging

log = logging.getLogger(__name__)


def rpc(method, params):
    from tui_gateway.server import handle_request

    response = handle_request({"jsonrpc": "2.0", "id": 1, "method": method, "params": params})
    if not isinstance(response, dict) or "result" not in response:
        raise RuntimeError("Hermes workspace handler failed")
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


def projects(_query):
    roster = rpc("profiles.list", {"include_sessions": False})
    groups, errors = [], []
    for profile in roster["profiles"]:
        name = profile["name"]
        try:
            tree = rpc("projects.tree", {"profile": name})
            groups.append({"profile": name, "projects": tree["projects"]})
        except Exception:
            log.exception("Companion project tree unavailable for a profile")
            errors.append({"profile": name, "message": "Project tree unavailable"})
    return {"groups": groups, "errors": errors}


def project_detail(query):
    profile, project_id = query.get("profile", ""), query.get("project_id", "")
    names = {p["name"] for p in rpc("profiles.list", {"include_sessions": False})["profiles"]}
    if profile not in names or not project_id:
        raise ValueError("A valid profile and project_id are required")
    return rpc("projects.project_sessions", {"profile": profile, "project_id": project_id})


def boards(_query):
    from plugins.kanban.dashboard.plugin_api import list_boards

    return list_boards(include_archived=False)


def board(query):
    from plugins.kanban.dashboard.plugin_api import get_board, list_boards

    slug = query.get("board", "")
    if slug not in {b["slug"] for b in list_boards(include_archived=False)["boards"]}:
        raise ValueError("Select an existing board")
    return get_board(tenant=None, include_archived=False, board=slug,
                     workflow_template_id=None, current_step_key=None)


READERS = {
    "projects": projects,
    "project": project_detail,
    "bots": bots,
    "bot-history": bot_history,
    "boards": boards,
    "board": board,
}


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
                return web.json_response(result, headers={"Cache-Control": "no-store"})
            except ValueError as exc:
                return web.json_response({"error": str(exc)}, status=400)
            except Exception:
                log.exception("Companion workspace read failed")
                return web.json_response({"error": "Hermes workspace data is unavailable"}, status=503)
        return read

    for path, reader in READERS.items():
        app.router.add_get("/api/companion/" + path, handler(reader))


def register(ctx):
    ctx.register_platform_handler("api_server", wire)
