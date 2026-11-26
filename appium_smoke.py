import subprocess
from http.server import ThreadingHTTPServer
from threading import Thread

from safari_smoke import ELEMENT_KEY, TestPage, command, wait_for_driver


def run_test(fixture_url):
    session = command("POST", "/session", {"capabilities": {"alwaysMatch": {
        "platformName": "iOS",
        "appium:automationName": "XCUITest",
        "appium:deviceName": "iPhone 17",
        "appium:platformVersion": "26.5",
        "appium:bundleId": "com.apple.mobilesafari",
        "appium:initialDeeplinkUrl": fixture_url,
        "appium:wdaLaunchTimeout": 180000,
        "appium:wdaConnectionTimeout": 60000,
    }}}, timeout=420)
    path = f'/session/{session["sessionId"]}'
    print("Appium session created", flush=True)
    try:
        context = command("GET", path + "/context")
        if context != "NATIVE_APP":
            raise AssertionError(f"Unexpected Appium context: {context}")
        command("POST", path + "/timeouts", {"implicit": 20000})
        link = command("POST", path + "/element", {
            "using": "-ios predicate string",
            "value": "type == 'XCUIElementTypeLink' AND label == 'Open result'",
        }, timeout=60)
        command("POST", f"{path}/element/{link[ELEMENT_KEY]}/click", {}, timeout=60)
        command("POST", path + "/element", {
            "using": "-ios predicate string",
            "value": "label == 'Link clicked'",
        }, timeout=60)
        print("PASS: Appium tapped the link in iPhone Safari and found the destination", flush=True)
    except Exception:
        try:
            print(command("GET", path + "/source", timeout=25), flush=True)
        except Exception as error:
            print(f"Unable to read Safari's accessibility tree: {error}", flush=True)
        raise
    finally:
        try:
            command("DELETE", path, timeout=10)
        except Exception as error:
            print(f"Appium session cleanup: {error}", flush=True)


if __name__ == "__main__":
    with ThreadingHTTPServer(("127.0.0.1", 0), TestPage) as server:
        Thread(target=server.serve_forever, daemon=True).start()
        with open("appium.log", "w") as log:
            with subprocess.Popen(
                ["appium", "server", "--address", "127.0.0.1", "--port", "4444", "--log-no-colors"],
                stdout=log, stderr=subprocess.STDOUT,
            ) as driver:
                try:
                    wait_for_driver(driver)
                    run_test(f"http://127.0.0.1:{server.server_port}/")
                finally:
                    if driver.poll() is None:
                        driver.terminate()
                        try:
                            driver.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            driver.kill()
