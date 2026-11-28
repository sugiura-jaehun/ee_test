require 'json'
require 'open3'
require 'tmpdir'
require 'selenium-webdriver'
require 'uri'

SAFARI = 'com.apple.mobilesafari'
APPLE_EPOCH = 978_307_200
DESTINATION_PATH = '/advisers'

def wait_until(seconds, message, &condition)
  Selenium::WebDriver::Wait.new(timeout: seconds, interval: 1, message: message).until(&condition)
end

def screen_positions(label)
  Dir.mktmpdir('safari-smoke') do |directory|
    screenshot = File.join(directory, 'screen.png')
    _, capture = Open3.capture2('xcrun', 'simctl', 'io', ENV.fetch('SIMULATOR_UDID'),
                              'screenshot', screenshot)
    raise 'Could not capture the iPhone screen' unless capture.success?

    positions, result = Open3.capture2(ENV.fetch('SAFARI_OCR_BIN'), screenshot, label)
    raise 'Could not read the iPhone screen' unless result.success?

    JSON.parse(positions)
  end
end

def scroll_for_link(driver, size, label)
  19.times do |scroll_count|
    position = screen_positions(label).find { |x, y| (0.05..0.95).cover?(x) && (0.14..0.63).cover?(y) }
    return position if position
    break if scroll_count == 18

    driver.execute_script('mobile: dragFromToForDuration', {
      duration: 0.3,
      fromX: (size.width * 0.5).round, fromY: (size.height * 0.60).round,
      toX: (size.width * 0.5).round, toY: (size.height * 0.25).round
    })
  end
  raise 'Expected link text was not visible in the tappable part of the screen after scrolling'
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
http.read_timeout = 120
caps = Selenium::WebDriver::Remote::Capabilities.new(
  'platformName' => 'iOS',
  'appium:automationName' => 'XCUITest',
  'appium:udid' => ENV.fetch('SIMULATOR_UDID'),
  'appium:webDriverAgentUrl' => 'http://127.0.0.1:8100',
  'appium:newCommandTimeout' => 240,
  'appium:settings[defaultActiveApplication]' => SAFARI,
  'appium:isHeadless' => true,
  'appium:noReset' => true,
  'appium:waitForIdleTimeout' => 2
)

begin
  puts 'Starting an Appium native session'
  driver = Selenium::WebDriver.for(:remote, url: 'http://127.0.0.1:4723',
                                 capabilities: [caps], http_client: http)
  puts 'Opening the start page in Safari'
  unless system('xcrun', 'simctl', 'openurl', ENV.fetch('SIMULATOR_UDID'), start_url.to_s)
    raise 'The simulator could not open the start URL'
  end
  size = driver.manage.window.size
  x, y = scroll_for_link(driver, size, start_label)
  tapped_at = Time.now.to_f - APPLE_EPOCH
  puts 'Tapping the visible consultation link through Appium XCUITest'
  driver.execute_script('mobile: tap', { x: (size.width * x).round, y: (size.height * y).round })
  wait_until(40, 'Safari did not record a successful visit to /advisers after the tap') do
    recently_visited?(history, start_url.host, tapped_at)
  end
  puts 'Reached /advisers; scrolling to the destination link'
  scroll_for_link(driver, size, destination_label)
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
  begin
    driver&.quit
  rescue Selenium::WebDriver::Error::InvalidSessionIdError
    warn 'Appium session already ended'
  end
end
