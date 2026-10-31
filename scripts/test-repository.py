#!/usr/bin/env python3
"""Pull the generated chart repository through an owned loopback listener."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import subprocess
import tempfile
import threading


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *_):
        pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository", type=Path, required=True)
    parser.add_argument("--charts", nargs="+", required=True)
    args = parser.parse_args()
    directory = args.repository.resolve(strict=True)
    with tempfile.TemporaryDirectory(prefix="helm-repository-", dir=os.environ.get("OPENSOHA_VERIFY_DIR")) as work:
        private = Path(work)
        (private / "cache").mkdir()
        (private / "pull").mkdir()
        environment = dict(os.environ, HELM_REPOSITORY_CONFIG=str(private / "repositories.yaml"),
                           HELM_REPOSITORY_CACHE=str(private / "cache"))
        handler = partial(QuietHandler, directory=str(directory))
        with ThreadingHTTPServer(("127.0.0.1", 0), handler) as server:
            thread = threading.Thread(target=server.serve_forever)
            thread.start()
            try:
                url = "http://127.0.0.1:" + str(server.server_port)
                subprocess.run(["helm", "repo", "add", "opensoha", url], env=environment, check=True, timeout=60)
                subprocess.run(["helm", "repo", "update"], env=environment, check=True, timeout=60)
                for chart in args.charts:
                    subprocess.run(["helm", "pull", "opensoha/" + chart, "--destination", str(private / "pull")],
                                   env=environment, check=True, timeout=60)
            finally:
                server.shutdown()
                thread.join(timeout=5)
                if thread.is_alive():
                    raise RuntimeError("owned Helm repository listener did not stop")


if __name__ == "__main__":
    main()
