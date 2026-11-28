require 'capybara'
require 'selenium-webdriver'
require 'uri'

start_url = ENV.fetch('SMOKE_START_URL')
start_label = ENV.fetch('SMOKE_START_LABEL')
destination_label = ENV.fetch('SMOKE_DESTINATION_LABEL')

browser = ENV.fetch('SMOKE_BROWSER', 'chrome')
capabilities = case browser
when 'safari-webdriver'
  {
    'platformName' => 'iOS',
    'browserName' => 'Safari',
    'appium:automationName' => 'Safari',
    'safari:useSimulator' => true,
    'safari:deviceUDID' => ENV.fetch('SIMULATOR_UDID')
  }
when 'safari'
  {
    'platformName' => 'iOS',
    'browserName' => 'Safari',
    'appium:automationName' => 'XCUITest',
    'appium:udid' => ENV.fetch('SIMULATOR_UDID'),
    'appium:deviceName' => 'iPhone 17',
    'appium:platformVersion' => '26.5',
    'appium:safariInitialUrl' => start_url,
    'appium:webviewConnectTimeout' => 25_000,
    'appium:webviewConnectRetries' => 50,
    'appium:wdaLaunchTimeout' => 360_000,
    'appium:wdaStartupRetries' => 1,
    'appium:noReset' => true
  }
when 'chrome'
  {
    'platformName' => 'Android',
    'browserName' => 'Chrome',
    'appium:automationName' => 'UiAutomator2',
    'appium:udid' => ENV.fetch('ANDROID_SERIAL'),
    'appium:chromedriverExecutableDir' => ENV.fetch('CHROMEDRIVER_CACHE_DIR'),
    'appium:noReset' => true
  }
else
  raise "Unsupported smoke-test browser: #{browser}"
end

Capybara.register_driver(:mobile_appium) do |app|
  http = Selenium::WebDriver::Remote::Http::Default.new
  http.read_timeout = 540 if browser.start_with?('safari')
  Capybara::Selenium::Driver.new(app, browser: :remote,
                                    url: 'http://127.0.0.1:4723',
                                    http_client: http,
                                    capabilities: [Selenium::WebDriver::Remote::Capabilities.new(capabilities)])
end

Capybara.default_max_wait_time = 35
session = Capybara::Session.new(:mobile_appium)
$stdout.sync = true

begin
  puts "Opening the start page in #{browser}"
  connection_attempts = 0
  begin
    session.visit(start_url)
  rescue Selenium::WebDriver::Error::SessionNotCreatedError,
         Selenium::WebDriver::Error::UnknownError => error
    connection_attempts += 1
    connection_timeout = error.message.match?(/not listening|timed out while connecting|RWIApplication/i)
    raise unless browser == 'safari-webdriver' && connection_timeout && connection_attempts < 3

    warn "Safari WebDriver connection timed out; retrying (attempt #{connection_attempts + 1} of 3)"
    sleep 3
    retry
  end
  start_link = session.find(:link, start_label, exact: true, match: :first)
  start_page = URI.parse(session.current_url)
  expected_path = URI.join(start_page.to_s, start_link[:href]).path
  raise 'Start link does not lead to a different page' if expected_path == start_page.path

  if browser.start_with?('safari')
    session.execute_script("arguments[0].scrollIntoView({ block: 'center' })", start_link)
    session.execute_script(<<~JS, start_link)
      const link = arguments[0];
      sessionStorage.removeItem('smoke-touch-events');
      for (const type of ['pointerdown', 'touchstart', 'click']) {
        document.addEventListener(type, event => {
          const events = JSON.parse(sessionStorage.getItem('smoke-touch-events') || '[]');
          events.push({ type, hitLink: link.contains(event.target), trusted: event.isTrusted });
          sessionStorage.setItem('smoke-touch-events', JSON.stringify(events));
        }, { capture: true, once: true });
      }
    JS
  end
  puts 'Tapping the start link'
  if browser == 'safari-webdriver'
    actions = session.driver.browser.action
    actions.add_pointer_input(:touch, 'finger')
    actions.click(start_link.native, device: 'finger').perform
  else
    start_link.click
  end
  unless session.has_current_path?(expected_path, ignore_query: true)
    if browser.start_with?('safari')
      events = session.evaluate_script("sessionStorage.getItem('smoke-touch-events')")
      warn "Events seen by the page: #{events || 'none'}"
      warn "Expected path: #{expected_path}; actual path: #{URI.parse(session.current_url).path}"
      warn "Open windows: #{session.windows.size}"
    end
    raise 'The browser did not reach the expected destination path after tapping the start link'
  end
  destination = session.find(:link, destination_label, exact: true, visible: :all, match: :first)
  puts 'Scrolling to the consultation link'
  session.execute_script("arguments[0].scrollIntoView({ block: 'center' })", destination)
  raise 'Consultation link is outside the visible screen' unless session.evaluate_script(<<~JS, destination)
    (() => {
      const { top, right, bottom, left } = arguments[0].getBoundingClientRect();
      const viewport = window.visualViewport;
      return top >= viewport.offsetTop && left >= viewport.offsetLeft &&
        bottom <= viewport.offsetTop + viewport.height &&
        right <= viewport.offsetLeft + viewport.width;
    })()
  JS

  puts 'PASS: the destination consultation link is visible'
ensure
  session.driver.quit
end
