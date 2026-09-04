"""Expose the FastAPI app through Azure Functions ASGI middleware."""
import azure.functions as func

from backend.main import app as fastapi_app


async def main(req: func.HttpRequest, context: func.Context) -> func.HttpResponse:
    return await func.AsgiMiddleware(fastapi_app).handle_async(req, context)
