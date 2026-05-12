import json
import re
from json import JSONDecodeError

from llm_protocol import (
    auth_headers,
    chat_payload,
    is_responses_endpoint,
    request_json,
    response_output_text,
    responses_payload,
)


def request_translation_text(settings, instructions, text, max_tokens=2048):
    provider = settings["provider"]
    endpoint = settings["endpoint"]
    token = settings["token"]
    model = settings["model"]

    if provider == "claude":
        payload = {
            "model": model,
            "max_tokens": max_tokens,
            "temperature": 0.2,
            "system": instructions,
            "messages": [{"role": "user", "content": text}],
        }
        result = request_json(endpoint, auth_headers(provider, endpoint, token), payload)
        parts = result.get("content", [])
        return "\n".join(item.get("text", "") for item in parts if item.get("type") == "text").strip()

    if is_responses_endpoint(endpoint):
        payload = responses_payload(model, instructions, text, max_tokens)
        result = request_json(endpoint, auth_headers(provider, endpoint, token), payload)
        translated = response_output_text(result)
        if not translated:
            raise RuntimeError("LLM response has no output text.")
        return translated

    payload = chat_payload(
        endpoint,
        model,
        [
            {"role": "system", "content": instructions},
            {"role": "user", "content": text},
        ],
        temperature=0.2,
    )
    result = request_json(endpoint, auth_headers(provider, endpoint, token), payload)
    choices = result.get("choices", [])
    if not choices:
        raise RuntimeError("LLM response has no choices.")
    return choices[0].get("message", {}).get("content", "").strip()


def request_translation_json(settings, system_prompt, user_prompt, max_tokens=8192):
    content = request_translation_text(settings, system_prompt, user_prompt, max_tokens=max_tokens)
    return parse_translation_json(content)


def parse_translation_json(content):
    text = content.strip()
    text = re.sub(r"^```(?:json)?\s*", "", text)
    text = re.sub(r"\s*```$", "", text)
    try:
        parsed = json.loads(text)
    except JSONDecodeError:
        start = text.find("[")
        end = text.rfind("]")
        if start == -1 or end == -1 or end <= start:
            raise
        parsed = json.loads(text[start : end + 1])

    if not isinstance(parsed, list):
        raise RuntimeError("LLM response is not a JSON array.")
    return parsed
