import asyncio
import json
import logging
import os
import ssl
import sys
from pathlib import Path

import aiohttp
from aiohttp import web, WSMsgType
from aiomqtt import Client, MqttError


OPTIONS_PATH = Path("/data/options.json")
MQTT_SERVICE_URL = "http://supervisor/services/mqtt"
HTTP_HOST = "0.0.0.0"
HTTP_PORT = 52341

SUFFIXES = ("data", "state", "warnings")

log = logging.getLogger("mqtt2api")


def load_options():
    if not OPTIONS_PATH.exists():
        raise RuntimeError(f"Options file not found: {OPTIONS_PATH}")
    try:
        raw = json.loads(OPTIONS_PATH.read_text())
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Invalid JSON in {OPTIONS_PATH}: {exc}") from exc

    api_secret = raw.get("api_secret") or ""
    if not api_secret:
        raise RuntimeError("api_secret is empty, set it in addon options")

    modules = raw.get("modules") or []
    if not isinstance(modules, list) or not modules:
        raise RuntimeError(
            "modules is empty, fill at least one module in addon options"
        )
    for module in modules:
        if not isinstance(module, str) or not module or "/" in module \
                or "+" in module or "#" in module:
            raise RuntimeError(f"Invalid module name: {module!r}")

    certfile = raw.get("certfile") or "/ssl/fullchain.pem"
    keyfile = raw.get("keyfile") or "/ssl/privkey.pem"
    for path in (certfile, keyfile):
        if not Path(path).is_file():
            raise RuntimeError(f"TLS file not found: {path}")

    log_level = (raw.get("log_level") or "warning").upper()
    if log_level not in ("DEBUG", "INFO", "WARNING", "ERROR"):
        raise RuntimeError(f"Invalid log_level: {log_level!r}")

    return {
        "api_secret": api_secret,
        "modules": modules,
        "certfile": certfile,
        "keyfile": keyfile,
        "log_level": log_level,
    }


def setup_logging(level_name):
    logging.basicConfig(
        level=getattr(logging, level_name),
        format="%(asctime)s %(levelname)s %(message)s",
        stream=sys.stdout,
    )


async def fetch_mqtt_credentials():
    token = os.environ.get("SUPERVISOR_TOKEN")
    if not token:
        raise RuntimeError("SUPERVISOR_TOKEN is not set")

    headers = {"Authorization": f"Bearer {token}"}
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(
                MQTT_SERVICE_URL, headers=headers, timeout=aiohttp.ClientTimeout(total=10)
            ) as resp:
                if resp.status != 200:
                    raise RuntimeError(
                        f"Supervisor MQTT API returned {resp.status}"
                    )
                body = await resp.json()
    except aiohttp.ClientError as exc:
        raise RuntimeError(f"Cannot reach Supervisor MQTT API: {exc}") from exc

    if not isinstance(body, dict) or body.get("result") != "ok":
        raise RuntimeError(f"Supervisor MQTT API error: {body}")

    data = body.get("data")
    if not isinstance(data, dict):
        raise RuntimeError(f"Supervisor MQTT API returned no data: {body}")

    host = data.get("host")
    port = data.get("port")
    username = data.get("username")
    password = data.get("password")
    if not host or not port or not username or not password:
        raise RuntimeError(f"Incomplete MQTT credentials from Supervisor: {data}")

    return {
        "host": host,
        "port": int(port),
        "username": username,
        "password": password,
    }


# --- Глобальное состояние ---

CFG = None
MQTT_CFG = None

devices = {}
websockets = set()
mqtt_client = None
mqtt_connected = False


def authorized(request):
    return request.headers.get("Authorization", "") == (
        "Bearer " + CFG["api_secret"]
    )


def require_auth(request):
    if not authorized(request):
        raise web.HTTPUnauthorized(
            text='{"error":"unauthorized"}',
            content_type="application/json",
        )


def valid_identifier(value):
    return (
        isinstance(value, str)
        and bool(value)
        and value not in (".", "..")
        and "/" not in value
        and "+" not in value
        and "#" not in value
    )


def module_enabled(module):
    return module in CFG["modules"]


def get_device_from_request(request):
    module = request.query.get("module", "")
    device_id = request.query.get("device_id", "")

    if not valid_identifier(module) or not valid_identifier(device_id):
        raise web.HTTPBadRequest(
            text='{"error":"invalid_device"}',
            content_type="application/json",
        )

    if not module_enabled(module):
        raise web.HTTPForbidden(
            text='{"error":"module_not_enabled"}',
            content_type="application/json",
        )

    return module, device_id


def get_device(module, device_id):
    key = f"{module}/{device_id}"
    return devices.setdefault(key, {
        "module": module,
        "device_id": device_id,
        "mqtt_connected": mqtt_connected,
        "device_state": None,
        "data": None,
        "last_data_received": None,
    })


async def broadcast(event):
    dead = []
    for ws in list(websockets):
        try:
            await ws.send_json(event)
        except Exception:
            dead.append(ws)
    for ws in dead:
        websockets.discard(ws)


async def mqtt_worker(app):
    global mqtt_client, mqtt_connected

    while True:
        try:
            async with Client(
                hostname=MQTT_CFG["host"],
                port=MQTT_CFG["port"],
                username=MQTT_CFG["username"],
                password=MQTT_CFG["password"],
            ) as client:
                mqtt_client = client
                mqtt_connected = True
                for device in devices.values():
                    device["mqtt_connected"] = True

                log.info("Connected to MQTT at %s:%s", MQTT_CFG["host"], MQTT_CFG["port"])

                await client.subscribe("+/+/data", qos=1)
                await client.subscribe("+/+/state", qos=1)
                await client.subscribe("+/+/warnings", qos=0)

                log.info("Subscribed to +/+/data, +/+/state, +/+/warnings")

                await broadcast({
                    "type": "connection",
                    "mqtt_connected": True,
                })

                async for message in client.messages:
                    topic = str(message.topic)
                    parts = topic.split("/")

                    if len(parts) != 3:
                        continue

                    module, device_id, suffix = parts
                    if suffix not in SUFFIXES:
                        continue
                    if not module_enabled(module):
                        continue

                    try:
                        payload = message.payload.decode("utf-8")
                    except UnicodeDecodeError:
                        log.warning("Non-UTF-8 MQTT payload on %s", topic)
                        continue

                    device = get_device(module, device_id)
                    event = {
                        "module": module,
                        "device_id": device_id,
                    }

                    if suffix == "data":
                        try:
                            data = json.loads(payload)
                        except json.JSONDecodeError:
                            log.warning("Invalid JSON in %s", topic)
                            continue

                        device["data"] = data
                        device["last_data_received"] = (
                            asyncio.get_running_loop().time()
                        )
                        event.update(type="data", data=data)

                    elif suffix == "state":
                        device["device_state"] = payload
                        event.update(type="state", state=payload)

                    else:
                        try:
                            warning = json.loads(payload)
                        except json.JSONDecodeError:
                            warning = {"raw": payload}
                        event.update(type="warning", warning=warning)

                    await broadcast(event)

        except asyncio.CancelledError:
            raise
        except MqttError as exc:
            log.warning("MQTT connection failed: %s", exc)
        except Exception:
            log.exception("Unexpected MQTT worker error")
        finally:
            mqtt_client = None
            mqtt_connected = False
            for device in devices.values():
                device["mqtt_connected"] = False
            await broadcast({
                "type": "connection",
                "mqtt_connected": False,
            })

        await asyncio.sleep(3)


async def start_mqtt(app):
    app["mqtt_task"] = asyncio.create_task(mqtt_worker(app))


async def stop_mqtt(app):
    task = app.get("mqtt_task")
    if task:
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass


async def get_state(request):
    require_auth(request)
    module, device_id = get_device_from_request(request)
    device = get_device(module, device_id)

    age = None
    last = device["last_data_received"]
    if last is not None:
        age = round(asyncio.get_running_loop().time() - last, 1)

    return web.json_response({
        "module": module,
        "device_id": device_id,
        "mqtt_connected": device["mqtt_connected"],
        "device_state": device["device_state"],
        "data": device["data"],
        "data_age_seconds": age,
    })


async def post_command(request):
    require_auth(request)
    module, device_id = get_device_from_request(request)

    if mqtt_client is None or not mqtt_connected:
        raise web.HTTPServiceUnavailable(
            text='{"error":"mqtt_disconnected"}',
            content_type="application/json",
        )

    try:
        body = await request.json()
    except (json.JSONDecodeError, ValueError):
        raise web.HTTPBadRequest(
            text='{"error":"invalid_json"}',
            content_type="application/json",
        )

    if not isinstance(body, dict):
        raise web.HTTPBadRequest(
            text='{"error":"expected_json_object"}',
            content_type="application/json",
        )

    command = body.get("command")
    if not isinstance(command, str) or not command:
        raise web.HTTPBadRequest(
            text='{"error":"invalid_command"}',
            content_type="application/json",
        )

    topic = f"{module}/{device_id}/cmd"

    try:
        await mqtt_client.publish(
            topic,
            json.dumps(body, separators=(",", ":")),
            qos=1,
            retain=False,
        )
    except MqttError:
        log.exception("MQTT command publish failed")
        raise web.HTTPServiceUnavailable(
            text='{"error":"publish_failed"}',
            content_type="application/json",
        )

    log.info("Published command %s to %s", command, topic)
    return web.json_response({
        "published": True,
        "topic": topic,
        "command": command,
        "module": module,
        "device_id": device_id,
    })


async def websocket_handler(request):
    require_auth(request)

    ws = web.WebSocketResponse(heartbeat=30)
    await ws.prepare(request)
    websockets.add(ws)

    await ws.send_json({
        "type": "initial",
        "mqtt_connected": mqtt_connected,
        "devices": list(devices.values()),
    })

    try:
        async for message in ws:
            if message.type == WSMsgType.ERROR:
                log.warning("WebSocket error: %s", ws.exception())
    finally:
        websockets.discard(ws)

    return ws


async def close_websockets(app):
    if websockets:
        await asyncio.gather(
            *(
                ws.close(code=1001, message=b"Server shutting down")
                for ws in list(websockets)
            ),
            return_exceptions=True,
        )


async def health(request):
    return web.json_response({"service": "mqtt2api", "ok": True})


def main():
    global CFG, MQTT_CFG

    try:
        CFG = load_options()
    except RuntimeError as exc:
        logging.basicConfig(level=logging.ERROR, stream=sys.stdout)
        log.error("Configuration error: %s", exc)
        sys.exit(1)

    setup_logging(CFG["log_level"])
    log.info("Options loaded: modules=%s log_level=%s",
             CFG["modules"], CFG["log_level"])

    try:
        MQTT_CFG = asyncio.run(fetch_mqtt_credentials())
    except RuntimeError as exc:
        log.error("MQTT credentials error: %s", exc)
        sys.exit(1)

    log.info("MQTT credentials obtained: %s:%s",
             MQTT_CFG["host"], MQTT_CFG["port"])

    app = web.Application(client_max_size=64 * 1024)
    app.router.add_get("/health", health)
    app.router.add_get("/api/state", get_state)
    app.router.add_post("/api/command", post_command)
    app.router.add_get("/ws", websocket_handler)

    app.on_startup.append(start_mqtt)
    app.on_shutdown.append(close_websockets)
    app.on_cleanup.append(stop_mqtt)

    ssl_context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
    ssl_context.load_cert_chain(CFG["certfile"], CFG["keyfile"])

    web.run_app(
        app,
        ssl_context=ssl_context,
        host=HTTP_HOST,
        port=HTTP_PORT,
        print=None,
    )


if __name__ == "__main__":
    main()
