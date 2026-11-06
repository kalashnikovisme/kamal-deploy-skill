#!/usr/bin/env python3
"""bin/console.d/python.py - application-aware REPL for plain Python / FastAPI projects.

Django (`manage.py shell`) and Flask (`flask shell`) use their native shells and never
reach this file. Here: put the project root on sys.path, load .env (python-dotenv if
installed, never overriding the real environment), expose a FastAPI/Starlette `app`
only if it is genuinely importable, then open IPython (autoawait) or the stdlib REPL.

A project can own the context via console_config.py exposing `context() -> dict`.
No server is started and nothing is migrated.
"""
import importlib
import os
import sys

root = os.getcwd()
sys.path.insert(0, root)
notes, ns = [], {}

try:
    from dotenv import load_dotenv
    for f in (".env", ".env.local"):
        if os.path.exists(f):
            load_dotenv(f, override=False)
except ImportError:
    pass


def _try_import(name):
    try:
        return importlib.import_module(name)
    except ModuleNotFoundError as e:
        if e.name and name.split(".")[0] != e.name.split(".")[0]:
            notes.append(f"{name}: missing dependency {e.name}")
        return None
    except Exception as e:  # import-time failure of application code
        notes.append(f"{name}: failed to import ({type(e).__name__}: {e})")
        return None


labels = []
if os.path.exists("console_config.py"):
    cfg = _try_import("console_config")
    if cfg and hasattr(cfg, "context"):
        ns.update(cfg.context())
        labels.append("console_config.py")
else:
    for modname in ("app.main", "main", "app", "src.main"):
        mod = _try_import(modname)
        app = getattr(mod, "app", None) if mod else None
        if app is not None and type(app).__name__ in ("FastAPI", "Starlette"):
            ns["app"] = app
            labels.append(f"{type(app).__name__} app from {modname} (no server started)")
            break

name = os.path.basename(root)
env = os.environ.get("APP_ENV") or os.environ.get("ENV") or os.environ.get("PYTHON_ENV") or "development"
print(f"{name} console ({env}, python {sys.version.split()[0]})")
if labels:
    print("  context: " + ", ".join(labels))
print("  available: " + ", ".join(["import <module>", "asyncio.run(...)"] + sorted(ns)))
for n in notes:
    print("  note:", n)

ns.update({"__name__": "__console__"})
try:
    from IPython import start_ipython
    from traitlets.config import Config
    c = Config()
    c.TerminalInteractiveShell.autoawait = True
    c.TerminalInteractiveShell.banner1 = ""
    start_ipython(argv=[], user_ns=ns, config=c)
except ImportError:
    import code
    try:
        import readline, rlcompleter  # noqa: F401  (history + tab completion where available)
        readline.set_completer(rlcompleter.Completer(ns).complete)
        readline.parse_and_bind("tab: complete")
    except ImportError:
        pass
    code.interact(banner="", local=ns, exitmsg="")
