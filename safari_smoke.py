import json
import subprocess
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import Thread
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

TEST_PAGES = {
    "/": b'<!doctype html><title>Link test</title><a id="test-link" href="/clicked">Open result</a>',
    "/clicked": b'<!doctype html><title>Click result</title><h1 id="result">Link clicked</h1>',
}
ELEMENT_KEY = "element-6066-11e4-a52e-4f735466cecf"


class TestPage(BaseHTTPRequestHandler):
    def do_GET(self):
        html = TEST_PAGES.get(self.path)
        if html is None:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(html)))
        self.end_headers()
        self.wfile.write(html)


def command(method, path, payload=None, timeout=30):
    body = None if payload is None else json.dumps(payload).encode()
    request = Request(
        f"http://127.0.0.1:4444{path}",
        data=body,
        headers={"Content-Type": "application/json"},
        method=method,
    )
    try:
        with urlopen(request, timeout=timeout) as response:
            return json.load(response)["value"]
    except HTTPError as error:
        raise RuntimeError(f"{method} {path}: {error.read().decode()}") from error


def wait_for_driver(process, timeout=30, name="safaridriver"):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f"{name} exited before becoming ready")
        try:
            command("GET", "/status", timeout=2)
            return
        except (URLError, TimeoutError):
            time.sleep(1)
    raise RuntimeError(f"{name} did not respond within {timeout} seconds")


def run_test(fixture_url):
    session = command("POST", "/session", {"capabilities": {"alwaysMatch": {
        "browserName": "safari",
        "platformName": "iOS",
        "safari:useSimulator": True,
        "safari:deviceName": "iPhone 17",
        "safari:platformVersion": "27.0",
    }}}, timeout=75)
    print("iPhone Safari session created", flush=True)
    path = f'/session/{session["sessionId"]}'
    try:
        command("POST", path + "/timeouts", {"pageLoad": 20000, "implicit": 10000})
        command("POST", path + "/url", {"url": fixture_url})
        print("Test page opened", flush=True)
        link = command("POST", path + "/element", {"using": "css selector", "value": "#test-link"})
        command("POST", f"{path}/element/{link[ELEMENT_KEY]}/click", {})
        command("POST", path + "/element", {"using": "css selector", "value": "#result"})
        url = command("GET", path + "/url")
        if url != fixture_url + "clicked":
            raise AssertionError(f"Unexpected URL after click: {url}")
        print("PASS: iPhone Safari clicked the link and displayed the result", flush=True)
    finally:
        try:
            command("DELETE", path, timeout=5)
        except (RuntimeError, URLError, TimeoutError) as error:
            print(f"Safari session cleanup: {error}", flush=True)


if __name__ == "__main__":
    with ThreadingHTTPServer(("127.0.0.1", 0), TestPage) as server:
        Thread(target=server.serve_forever, daemon=True).start()
        with subprocess.Popen(["/usr/bin/safaridriver", "-p", "4444"]) as driver:
            try:
                wait_for_driver(driver)
                print("Safari WebDriver is ready", flush=True)
                run_test(f"http://127.0.0.1:{server.server_port}/")
            finally:
                if driver.poll() is None:
                    driver.terminate()
