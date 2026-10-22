import argparse
import asyncio
import sys

from pydantic import ValidationError

from gateway_agent.agent import build_agent
from gateway_agent.config import Settings


async def _ask(agent, prompt: str, session, stream: bool) -> None:
    if stream:
        started = False
        async for chunk in agent.run(prompt, session=session, stream=True):
            if chunk.text:
                if not started:
                    print("Agent: ", end="", flush=True)
                    started = True
                print(chunk.text, end="", flush=True)
        if started:
            print()
    else:
        print(f"Agent: {await agent.run(prompt, session=session)}")


async def _run(prompt: str | None, stream: bool) -> None:
    agent = build_agent(Settings())
    session = agent.create_session()

    if prompt:
        await _ask(agent, prompt, session, stream)
        return

    print("Chat with the gateway agent. Empty line or Ctrl-D to quit.")
    while True:
        try:
            text = (await asyncio.to_thread(input, "You: ")).strip()
        except EOFError:
            return
        if not text:
            return
        try:
            await _ask(agent, text, session, stream)
        except Exception as exc:  # keep the chat alive on gateway errors
            print(f"\nerror: {exc}", file=sys.stderr)


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="gateway-agent",
        description="Agent Framework agent that calls a model through the APIM gateway.",
    )
    parser.add_argument("prompt", nargs="?", help="ask once and exit (default: interactive chat)")
    parser.add_argument("--no-stream", action="store_true", help="wait for the full answer")
    args = parser.parse_args()

    try:
        asyncio.run(_run(args.prompt, stream=not args.no_stream))
    except ValidationError as exc:
        fields = ", ".join(f"GATEWAY_{str(e['loc'][0]).upper()}" for e in exc.errors())
        print(f"Invalid configuration ({fields}). See app/.env.example.", file=sys.stderr)
        for e in exc.errors():
            print(f"  {e['loc'][0]}: {e['msg']}", file=sys.stderr)
        sys.exit(2)
    except Exception as exc:  # a gateway or model error: show the message, not a traceback
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
