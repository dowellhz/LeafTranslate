import json
import urllib.error
import urllib.request
from urllib.parse import urlparse


def request_json(url, headers, payload):
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(url, data=data, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"LLM request failed: {exc.code}\n{body}") from exc


def is_azure_endpoint(endpoint):
    host = (urlparse(endpoint).hostname or "").lower()
    return (
        host.endswith(".openai.azure.com")
        or host.endswith(".services.ai.azure.com")
        or host.endswith(".cognitiveservices.azure.com")
    )


def is_azure_deployment_endpoint(endpoint):
    return is_azure_endpoint(endpoint) and "/openai/deployments/" in urlparse(endpoint).path.lower()


def is_responses_endpoint(endpoint):
    path = urlparse(endpoint).path.lower()
    return path.endswith("/openai/responses") or path.endswith("/openai/v1/responses")


def auth_headers(provider, endpoint, token):
    headers = {"Content-Type": "application/json"}
    if provider == "claude":
        headers["x-api-key"] = token
        headers["anthropic-version"] = "2023-06-01"
    elif is_azure_endpoint(endpoint):
        headers["api-key"] = token
    else:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def chat_payload(endpoint, model, messages, temperature=0.2):
    payload = {
        "messages": messages,
        "temperature": temperature,
    }
    if not is_azure_deployment_endpoint(endpoint):
        payload["model"] = model
    return payload


def responses_payload(model, instructions, input_text, max_output_tokens):
    return {
        "model": model,
        "instructions": instructions,
        "input": input_text,
        "max_output_tokens": max_output_tokens,
    }


def response_output_text(result):
    output_text = result.get("output_text")
    if isinstance(output_text, str) and output_text.strip():
        return output_text.strip()

    output = result.get("output", [])
    parts = []
    if isinstance(output, list):
        for item in output:
            content = item.get("content", []) if isinstance(item, dict) else []
            if not isinstance(content, list):
                continue
            for block in content:
                if not isinstance(block, dict):
                    continue
                text = block.get("text") or block.get("content")
                if isinstance(text, str):
                    parts.append(text)
    return "\n".join(parts).strip()
