require 'open3'
require 'selenium-webdriver'
require 'uri'

SAFARI = 'com.apple.mobilesafari'
APPLE_EPOCH = 978_307_200
DESTINATION_PATH = '/advisers'

def wait_until(seconds, message, &condition)
  Selenium::WebDriver::Wait.new(timeout: seconds, interval: 1, message: message).until(&condition)
end

def visible_link(driver, label, match: '==')
  escaped = label.gsub(/[\\"]/){ |character| "\\#{character}" }
  predicate = %(type == "XCUIElementTypeLink" AND (label #{match} "#{escaped}" OR name #{match} "#{escaped}"))
  driver.find_elements('-ios predicate string', predicate).find(&:displayed?)
rescue Selenium::WebDriver::Error::StaleElementReferenceError
  nil
end

def scroll_for_link(driver, label, match: '==')
  size = driver.manage.window.size
  11.times do |scroll_count|
    link = visible_link(driver, label, match: match)
    return link if link
    break if scroll_count == 10

    driver.execute_script('mobile: dragFromToForDuration', {
      duration: 0.3,
      fromX: size.width * 0.5, fromY: size.height * 0.58,
      toX: size.width * 0.5, toY: size.height * 0.22
    })
  end
  raise 'Expected link did not become visible after scrolling'
end

def recently_visited?(history, host, after)
  return false unless File.file?(history)

  sql = <<~SQL
    SELECT item.url
    FROM history_visits visit JOIN history_items item ON item.id = visit.history_item
    WHERE visit.visit_time >= #{Float(after)} AND visit.load_successful = 1
    ORDER BY visit.visit_time DESC LIMIT 30;
  SQL
  urls, status = Open3.capture2('sqlite3', '-readonly', history, sql)
  status.success? && urls.lines.any? do |line|
    url = URI.parse(line.strip)
    url.host == host && url.path.sub(%r{/$}, '') == DESTINATION_PATH
  rescue URI::InvalidURIError
    false
  end
end

$stdout.sync = true
start_url = URI(ENV.fetch('SMOKE_START_URL'))
start_label = ENV.fetch('SMOKE_START_LABEL')
destination_label = ENV.fetch('SMOKE_DESTINATION_LABEL')
history = ENV.fetch('SAFARI_HISTORY_DB')
http = Selenium::WebDriver::Remote::Http::Default.new
http.read_timeout = 400
caps = Selenium::WebDriver::Remote::Capabilities.new(
  'platformName' => 'iOS',
  'appium:automationName' => 'XCUITest',
  'appium:bundleId' => SAFARI,
  'appium:udid' => ENV.fetch('SIMULATOR_UDID'),
  'appium:initialDeeplinkUrl' => start_url.to_s,
  'appium:isHeadless' => true,
  'appium:noReset' => true,
  'appium:wdaLaunchTimeout' => 300_000,
  'appium:wdaStartupRetries' => 1,
  'appium:waitForIdleTimeout' => 2
)

begin
  puts 'Opening Safari through Appium in native mode'
  driver = Selenium::WebDriver.for(:remote, url: 'http://127.0.0.1:4723',
                                 capabilities: [caps], http_client: http)
  wait_until(75, 'Safari did not expose the web page') do
    driver.find_elements('-ios predicate string', 'type == "XCUIElementTypeWebView"').any?
  end
  link = scroll_for_link(driver, start_label)
  tapped_at = Time.now.to_f - APPLE_EPOCH
  puts 'Tapping the consultation link through Appium XCUITest'
  link.click
  wait_until(40, 'Safari did not record a successful visit to /advisers after the tap') do
    recently_visited?(history, start_url.host, tapped_at)
  end
  puts 'Reached /advisers; scrolling to the destination link'
  scroll_for_link(driver, destination_label, match: 'CONTAINS')
  puts 'PASS: Safari opened /advisers and displayed the destination link'
rescue StandardError
  if driver
    begin
      File.write(File.join(ENV.fetch('RUNNER_TEMP'), 'ios-appium-recording', 'safari-source.xml'), driver.page_source)
    rescue Selenium::WebDriver::Error::WebDriverError
      warn 'Safari accessibility tree unavailable'
    end
  end
  raise
ensure
  driver&.quit
end
