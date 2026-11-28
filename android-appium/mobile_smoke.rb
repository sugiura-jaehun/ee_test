require 'capybara'
require 'selenium-webdriver'
require 'uri'

start_url = ENV.fetch('SMOKE_START_URL')
start_label = ENV.fetch('SMOKE_START_LABEL')
destination_label = ENV.fetch('SMOKE_DESTINATION_LABEL')

Capybara.register_driver(:android_appium) do |app|
  capabilities = Selenium::WebDriver::Remote::Capabilities.new(
    'platformName' => 'Android',
    'browserName' => 'Chrome',
    'appium:automationName' => 'UiAutomator2',
    'appium:udid' => ENV.fetch('ANDROID_SERIAL'),
    'appium:chromedriverExecutableDir' => ENV.fetch('CHROMEDRIVER_CACHE_DIR'),
    'appium:noReset' => true
  )
  Capybara::Selenium::Driver.new(app, browser: :remote,
                                    url: 'http://127.0.0.1:4723',
                                    capabilities: [capabilities])
end

Capybara.default_max_wait_time = 35
session = Capybara::Session.new(:android_appium)

begin
  puts 'Opening the start page in Android Chrome'
  session.visit(start_url)
  start_link = session.find(:link, start_label, exact: true, match: :first)
  start_page = URI.parse(session.current_url)
  expected_path = URI.join(start_page.to_s, start_link[:href]).path
  raise 'Start link does not lead to a different page' if expected_path == start_page.path

  puts 'Tapping the start link'
  start_link.click
  unless session.has_current_path?(expected_path, ignore_query: true)
    raise 'Chrome did not reach the expected destination path after tapping the start link'
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
