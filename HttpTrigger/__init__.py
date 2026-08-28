"""Azure Functions entry point: serves the FastAPI app (backend.main) through the
ASGI adapter. Uses the function.json (host-indexed) model so the app runs reliably
from a read-only run-from-package mount, where Python worker indexing does not."""
import azure.functions as func

from backend.main import app as fastapi_app


async def main(req: func.HttpRequest, context: func.Context) -> func.HttpResponse:
    return await func.AsgiMiddleware(fastapi_app).handle_async(req, context)
