require 'capybara'
require 'selenium-webdriver'
require 'uri'

start_url = ENV.fetch('SMOKE_START_URL')
start_label = ENV.fetch('SMOKE_START_LABEL')
destination_label = ENV.fetch('SMOKE_DESTINATION_LABEL')

browser = ENV.fetch('SMOKE_BROWSER', 'chrome')
capabilities = case browser
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
  http.read_timeout = 540 if browser == 'safari'
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
  session.visit(start_url)
  start_link = session.find(:link, start_label, exact: true, match: :first)
  start_page = URI.parse(session.current_url)
  expected_path = URI.join(start_page.to_s, start_link[:href]).path
  raise 'Start link does not lead to a different page' if expected_path == start_page.path

  puts 'Tapping the start link'
  start_link.click
  unless session.has_current_path?(expected_path, ignore_query: true)
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
