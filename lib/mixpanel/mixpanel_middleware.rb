require 'rack'

class MixpanelMiddleware
  def initialize(app, mixpanel_token)
    @app = app
    @token = mixpanel_token
  end

  def call(env)
    @env = env['rack.session']
    @status, @headers, @response = @app.call(env)

    events_rendered = update_response!
    update_content_length!
    delete_event_queue! if events_rendered

    [@status, @headers, @response]
  end

  private

  def update_response!
    events_rendered = false
    @response.each do |part|
      if is_regular_request? && is_html_response?
        part.gsub!("</head>", "#{render_event_tracking_scripts}</head>")
        events_rendered = true
      end
    end

    events_rendered
  end

  def update_content_length!
    new_size = 0
    @response.each{|part| new_size += part.bytesize}
    @headers.merge!("Content-Length" => new_size.to_s)
  end

  def is_regular_request?
    !is_ajax_request?
  end

  def is_ajax_request?
    @env.has_key?("HTTP_X_REQUESTED_WITH") && @env["HTTP_X_REQUESTED_WITH"] == "XMLHttpRequest"
  end

  def is_html_response?
    @headers["Content-Type"].include?("text/html") if @headers.has_key?("Content-Type")
  end

  def is_javascript_response?
    @headers["Content-Type"].include?("text/javascript") if @headers.has_key?("Content-Type")
  end

  def delete_event_queue!
    @env.delete('mixpanel_events')
  end

  def queue
    return [] if !@env.has_key?('mixpanel_events') || @env['mixpanel_events'].empty?
    @env['mixpanel_events']
  end

  def render_event_tracking_scripts(include_script_tag=true)
    return "" if queue.empty?

    output = queue.map {|event| %(Mixpanel.track("#{event[:event]}", #{event[:properties].to_json});) }.join("\n")

    output = "try {#{output}} catch(err) {}"

    include_script_tag ? "<script type='text/javascript'>#{output}</script>" : output
  end
end
