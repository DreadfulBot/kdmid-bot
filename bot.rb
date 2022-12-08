require 'rubygems'
# require 'dotenv'
require 'bundler/setup'
Bundler.require(:default)
require 'telegram/bot'

Watir.default_timeout = 180

class Bot
  attr_reader :link, :browser, :client, :current_time

  def load(kdmid_subdomain, order_id, code)
    @link = "http://#{kdmid_subdomain}.kdmid.ru/queue/OrderInfo.aspx?id=#{order_id}&cd=#{code}"
    @client = TwoCaptcha.new(ENV.fetch('TWO_CAPTCHA_KEY'))
    @current_time = Time.now.utc.localtime("+03:00").to_s
    puts '[x] Loading...'

    options = {
    }

    proxy = {
      ssl: '',
      http: ''
    }

    if ENV['BROWSER_PROFILE']
      options.merge!(profile: ENV['BROWSER_PROFILE'])
    end
    @browser = Watir::Browser.new(
      ENV.fetch('BROWSER').to_sym,
      url: "http://#{ENV.fetch('HUB_HOST')}/wd/hub",
      options: options,
      # proxy: proxy
    )
  end

  def notify_user(message)
    puts message
    # `say "#{message}"`
    return unless ENV['TELEGRAM_TOKEN']

    Telegram::Bot::Client.run(ENV['TELEGRAM_TOKEN']) do |bot|
      bot.api.send_message(chat_id: ENV['TELEGRAM_CHAT_ID'], text: message)
    end
  end

  def pass_ddosprotect
    begin
      iframe = browser.iframe(id: 'ddg-iframe')
      iframe.wait_until(timeout: 30, &:exists?)
    rescue
      puts "ddos protect windows not detected"
      return
    end

    iframe = browser.iframe(id: 'ddg-iframe')

    puts 'waiting ddg-captcha checkbox'

    checkbox = iframe.div(class: 'ddg-captcha__checkbox')
    checkbox.wait_until(timeout: 60, &:exists?)

    puts 'clicking not robot button'

    checkbox.click

    captcha_image = iframe.images(class: 'ddg-modal__captcha-image').first

    captcha_image.wait_until(timeout: 20, &:exists?)

    sleep 5

    captcha_src = captcha_image.src

    regex = /\Adata:([-\w]+\/[-\w\+\.]+)?;base64,(.*)/m

    data_uri_parts = captcha_src.match(regex) || []

    puts 'save captcha image to file...'

    image_filepath = "./captches/#{current_time}.png"

    File.open(image_filepath, 'wb') do |f|
      f.write(Base64.decode64(data_uri_parts[2]))
    end

    puts 'decode captcha...'

    captcha = client.decode!(path: image_filepath)
    captcha_code = captcha.text

    puts "[x] ddosprotect captcha_code: #{captcha_code}"

    text_field = iframe.text_field(class: 'ddg-modal__input')
    text_field.set captcha_code

    iframe.button(class: 'ddg-modal__submit').click
  end

  def pass_hcaptcha
    sleep 5

    return unless browser.div(id: 'h-captcha').exists?

    sitekey = browser.div(id: 'h-captcha').attribute_value('data-sitekey')
    puts "sitekey: #{sitekey} url: #{browser.url}"

    captcha = client.decode_hcaptcha!(sitekey: sitekey, pageurl: browser.url)
    captcha_response = captcha.text
    puts "captcha_response: #{captcha_response}"

    3.times do |i|
      puts "attempt: #{i}"
      sleep 2
      ['h-captcha-response', 'g-recaptcha-response'].each do |el_name|
        browser.execute_script(
          "document.getElementsByName('#{el_name}')[0].style = '';
           document.getElementsByName('#{el_name}')[0].innerHTML = '#{captcha_response.strip}';
           document.querySelector('iframe').setAttribute('data-hcaptcha-response', '#{captcha_response.strip}');"
        )
      end
      sleep 3
      browser.execute_script("cb();")
      sleep 3
      break unless browser.div(id: 'h-captcha').exists?
    end

    if browser.div(id: 'h-captcha').exists?
      raise "Cannot pass captcha guard"
    end

    if browser.alert.exists?
      browser.alert.ok
    end
  end

  def pass_captcha_on_form
    sleep 3

    if browser.alert.exists?
      browser.alert.ok
      puts 'alert found'
    end

    puts "let's find the captcha image..."
    captcha_image = browser.images(id: 'ctl00_MainContent_imgSecNum').first
    captcha_image.wait_until(timeout: 5, &:exists?)

    puts 'save captcha image to file...'
    image_filepath = "./captches/#{current_time}.png"
    File.write(image_filepath, captcha_image.to_png)

    puts 'decode captcha...'
    captcha = client.decode!(path: image_filepath)
    captcha_code = captcha.text
    puts "[x] captcha_code: #{captcha_code}"

    text_field = browser.text_field(id: 'ctl00_MainContent_txtCode')
    text_field.set captcha_code
  end

  def click_make_appointment_button
    make_appointment_btn = browser.button(id: 'ctl00_MainContent_ButtonB')
    make_appointment_btn.wait_until(timeout: 60, &:exists?)
    make_appointment_btn.click
  end

  def save_page
    browser.screenshot.save "./screenshots/#{current_time}.png"
    File.open("./pages/#{current_time}.html", 'w') { |f| f.write browser.html }
  end

  def check_queue(kdmid_subdomain, order_id, code)
    load(kdmid_subdomain, order_id, code)

    puts "===== Current time: #{current_time} ====="

    puts "going to to link #{link}..."

    browser.goto link

    puts "passing hcaptcha..."

    pass_hcaptcha

    puts "[x] captcha passed"

    puts "[x] passing ddos protect"

    pass_ddosprotect

    puts "waiting main page load..."

    browser.wait_until(timeout: 50) { |b| b.title =~ /Очередь.*/i }

    puts "[x] page loaded"

    pass_captcha_on_form

    puts "pressing button main_content button A..."

    browser.button(id: 'ctl00_MainContent_ButtonA').click

    puts "[x] main_content button pressed"

    sleep 3

    puts "checking alert window..."

    if browser.alert.exists?
      browser.alert.ok
      puts "[x] alert window passed"
    end

    sleep 1

    puts "passing hcaptcha..."

    pass_hcaptcha

    puts "[x] hcaptcha passed"

    puts "clicking make appointment button..."

    click_make_appointment_button

    puts "[x] appointment button clicked"

    puts "saving page..."

    save_page

    puts "[x] page saved"

    puts "checking test phrase on page..."
    
    bad_gateway_error = browser.p(text: /Bad Gateway/).exists?

    if bad_gateway_error
      raise "502 Error on page"
    end

    stop_text_found = browser.p(text: /Извините, но в настоящий момент/).exists? || browser.p(text: /Свободное время в системе записи отсутствует/).exists?

    status = ''

    unless stop_text_found
      status = '[x] NEW TIME FOR AN APPOINTMENT FOUND!' 
    else
      status = '[x] No new appointments' 
    end

    message_start = "For #{kdmid_subdomain} - #{status}\nCheck link is #{link}\n"

    browser.close

    puts '=' * 50

    return message_start
  rescue Exception => e
    if browser
      browser.close
    end
    raise e
  end
  
  def check_all_queues
    subdomains = ENV.fetch("KDMID_SUBDOMAIN").split(',')
    order_ids = ENV.fetch("ORDER_ID").split(',')
    codes = ENV.fetch("CODE").split(',')

    final_message = "====[ QUEUES CHECKING STARTED ]====\n"

    subdomains.each_with_index do |subdomain, index|
      begin
        repeat_counter = 3
        while repeat_counter > 0 do
          begin
            queue_message = check_queue(subdomain, order_ids[index], codes[index])
            final_message = "#{final_message}\n\n#{queue_message}"
            break
          rescue Exception => e
            repeat_counter = repeat_counter - 1
          end
        end

        if repeat_counter == 0
            notify_user("[x] Exception! for subdomain #{subdomain}\n#{e.message}")
        end
      end
    end

    notify_user(final_message)
  end
end

# Bot.new.check_queue
# Dotenv.load
Bot.new.check_all_queues