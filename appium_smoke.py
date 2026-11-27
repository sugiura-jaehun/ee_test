import os
import subprocess
import time
from http.server import ThreadingHTTPServer
from threading import Event, Thread
from xml.etree import ElementTree

from safari_smoke import ELEMENT_KEY, TestPage, command, wait_for_driver


fixture_loaded = Event()
destination_loaded = Event()


class ObservedTestPage(TestPage):
    def do_GET(self):
        super().do_GET()
        if self.path == "/":
            fixture_loaded.set()
        elif self.path == "/clicked":
            destination_loaded.set()


def capabilities(fixture_url):
    mode = os.environ["APPIUM_MODE"]
    if mode == "safari-driver":
        return {
            "platformName": "iOS",
            "browserName": "Safari",
            "appium:automationName": "Safari",
            "safari:useSimulator": True,
            "safari:deviceUDID": os.environ["SIMULATOR_UDID"],
        }
    caps = {
        "platformName": "iOS",
        "appium:automationName": "XCUITest",
        "appium:udid": os.environ["SIMULATOR_UDID"],
        "appium:deviceName": "iPhone 17",
        "appium:platformVersion": "26.5",
        "appium:bundleId": "com.apple.mobilesafari",
        "appium:initialDeeplinkUrl": fixture_url,
        "appium:isHeadless": True,
        "appium:wdaLaunchTimeout": 480000,
        "appium:wdaConnectionTimeout": 90000,
        "appium:wdaStartupRetries": 1,
        "appium:waitForIdleTimeout": 3,
        "appium:showXcodeLog": True,
    }
    if mode == "xcuitest-attach":
        caps["appium:webDriverAgentUrl"] = "http://127.0.0.1:8100"
    return caps


def run_test(fixture_url):
    caps = capabilities(fixture_url)
    caps.pop("appium:bundleId")
    caps.pop("appium:initialDeeplinkUrl")
    caps["appium:includeSafariInWebviews"] = True
    caps["appium:noReset"] = True
    caps["appium:newCommandTimeout"] = 300
    caps["appium:settings[defaultActiveApplication]"] = "com.apple.mobilesafari"
    print(f"Starting an Appium session with {os.environ['APPIUM_MODE']}", flush=True)
    session = command("POST", "/session", {"capabilities": {"alwaysMatch": caps}}, timeout=660)
    path = f'/session/{session["sessionId"]}'
    print("Appium session created", flush=True)
    try:
        command("POST", path + "/timeouts", {"implicit": 25000})
        if caps["appium:automationName"] == "Safari":
            command("POST", path + "/url", {"url": fixture_url}, timeout=60)
            link = {"using": "css selector", "value": "#test-link"}
            result = {"using": "css selector", "value": "#result"}
        else:
            open_url = subprocess.Popen(
                ["xcrun", "simctl", "openurl", os.environ["SIMULATOR_UDID"], fixture_url],
            )
            try:
                if not fixture_loaded.wait(timeout=120):
                    raise AssertionError("Safari did not request the fixture page")
            finally:
                if open_url.poll() is None:
                    open_url.terminate()
                    try:
                        open_url.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        open_url.kill()
                        open_url.wait()
            print("Safari requested the fixture URL", flush=True)
            deadline = time.monotonic() + 120
            webviews = []
            while time.monotonic() < deadline:
                contexts = command("GET", path + "/contexts", timeout=60)
                print(f"Available contexts: {contexts}", flush=True)
                webviews = [context for context in contexts if context.startswith("WEBVIEW")]
                if webviews:
                    break
                time.sleep(3)
            if not webviews:
                raise AssertionError(f"No Safari web context found: {contexts}")
            command("POST", path + "/context", {"name": webviews[0]}, timeout=90)
            print("Switched to Safari web context", flush=True)
            element = command("POST", path + "/element", {"using": "css selector", "value": "#test-link"}, timeout=90)
            print("Found DOM link", flush=True)
            command("POST", f"{path}/element/{element[ELEMENT_KEY]}/click", {}, timeout=120)
            print("Clicked DOM link", flush=True)
            if not destination_loaded.wait(timeout=60):
                raise AssertionError("DOM click did not request destination")
            command("POST", path + "/element", {"using": "css selector", "value": "#result"}, timeout=90)
            print("PASS: Appium web context clicked and displayed the destination", flush=True)
            return
        element = command("POST", path + "/element", link, timeout=90)
        print("Fixture link found", flush=True)
        command("POST", f"{path}/element/{element[ELEMENT_KEY]}/click", {}, timeout=90)
        if caps["appium:automationName"] == "Safari":
            print(f"URL after tap: {command('GET', path + '/url')}", flush=True)
        command("POST", path + "/element", result, timeout=90)
        print("PASS: Appium tapped the link in iPhone Safari and found the destination", flush=True)
    except Exception:
        try:
            print(command("GET", path + "/source", timeout=90), flush=True)
        except Exception as error:
            print(f"Unable to read Safari's accessibility tree: {error}", flush=True)
        raise
    finally:
        try:
            command("DELETE", path, timeout=10)
        except Exception as error:
            print(f"Appium session cleanup: {error}", flush=True)


if __name__ == "__main__":
    with ThreadingHTTPServer(("127.0.0.1", 0), ObservedTestPage) as server:
        Thread(target=server.serve_forever, daemon=True).start()
        with open("appium.log", "w") as log:
            with subprocess.Popen(
                ["appium", "server", "--address", "127.0.0.1", "--port", "4444", "--log-no-colors"],
                stdout=log, stderr=subprocess.STDOUT,
            ) as driver:
                try:
                    wait_for_driver(driver, timeout=180, name="Appium")
                    print("Appium HTTP endpoint is ready", flush=True)
                    run_test(f"http://127.0.0.1:{server.server_port}/")
                finally:
                    if driver.poll() is None:
                        driver.terminate()
                        try:
                            driver.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            driver.kill()
