# Ruby 2.7 AWS Lambda

require 'uri'
require 'open-uri'
require 'net/http'
require 'json'
require 'aws-sdk-s3'
require 'sendgrid-ruby'
require_relative 'template'
require_relative 'keys'
include SendGrid

DEFAULT_SUBJECT = 'Zenput Notification'
DEFAULT_MESSAGE = 'Something went wrong! If you expected a report but did not receive one, you can reply to this message and our friendly technology helpers will investigate the problem.'
LOGGING         = true
ALERT           = true
DEFAULT_SENDER  = ENV['SENDER_ADDRESS']
ALERT_RECIPIENT = ENV['ALERT_RECIPIENT']
ENV['SENDGRID_API_KEY'] ||= SENDGRID_API_KEY
ENV['ZENPUT_API_KEY']   ||= ZENPUT_API_KEY

def __test(event=DUMMY_EVENT)
    # For console testing... use Lambda testing if in Lambda.
    handler(event: event, context: DUMMY_CONTEXT)
end

def handler(event:, context:)
    squawk if event.nil? || context.nil?
    form_id = event['Records'][0]['body']
    options = [ENV['OPTIONS']]
    if (form_id)
        digest = make_digest(form_id)
        render(digest,options)
    else
        squawk('Error: ' + context.invoked_function_arn, "No form-id <br/>" + event.to_json, false)
    end

    {
      "statusCode": 200,
      "headers": {
        "Content-Type": "application/json"
      },
      "isBase64Encoded": false,
      "body": event.to_json
    }
end

def make_digest(id)
    body = fetch_form(id)
    findings = filter_interesting(body)
    store = body.dig("fields", 0, "account", "name") || "No store specified"
    city  = body.dig("fields", 0, "account", "city") || "No city specified"
    digest = {}
    digest['recipient'] = ALERT_RECIPIENT #body.dig("fields", 0, "account", "email") || ALERT_RECIPIENT
    digest['title']     = body.dig("metadata", "title")
    digest['body'] = EMAIL_PRE + "<body><p>\n#{body['metadata']['title']}<br/> #{store} : #{city} </p>
            <table class='b'><th class='b' style='min-width:35%;'>Form Item</th><th class='b'>Answer</th>
            <th class='b' style='max-width:55%'>Details</th>\n" + findings.join + "
            </table>\n</body></html>"
    digest
end

def render(payload, options)
    options[0] && options.each { |o|
        o == "email"       && send_mail(DEFAULT_SENDER, "Digest: " + payload['title'], payload['recipient'], payload['body'])
        o == "console"     && puts(payload['body'])
        o == "s3"          && render_s3(payload)
        o == "browser"     && render_browser(payload)
    }
    log("Rendered with options: #{options.inspect}")
end

def render_browser(payload)
    File.open('outputs/browser_out.html', 'w') { |file| 
        file.write(payload['body']) 
    }
    if RUBY_PLATFORM.include?('darwin')
        `open -a Firefox outputs/browser_out.html`
    else
        `firefox outputs/browser_out.html`
    end
end

def render_s3(payload)
    #foo
end

def fetch_form(id)
    puts "fetching: " + id
    res = URI.open('https://www.zenput.com/api/v1/forms/get/' +  id,
                     'x-api-token' => ENV['ZENPUT_API_KEY']).read
    JSON.parse(res)
end

def filter_interesting(body)
    field_order                             = body['metadata']['order'].map {|o| o.to_i}
    fields                                  = body['fields']
    ordered_fields                          = []
    collection = []
    # Deliver us from nested iteration, in Your name we pray...                                                                                         nested 
    field_order.each_with_index() { |id, ndx| 
        f             =      ordered_fields[ndx]   = fields.find { |w| w['id'] == id }                                                                    #              
        # f[:this_index]                             = ndx
        # f[:prev_id]                                = field_order[ndx-1] unless ndx == 0
        f[:next_id]                                = field_order[ndx+1]
        f[:next_id]   && f[:next_field_parent_id]  = fields.find { |w| w['id'] == f[:next_id] }['metadata']['dependent_parent_id']                        #
        f[:parent_id]                              = f['metadata']['dependent_parent_id']
        # f[:parent_id] && f[:parent_index]          = ordered_fields[ndx..ndx-3].find_index { |w| w[:id] == f[:parent_id] }                                #    if we need type: # && f[:parent_type]           = ordered_fields[f[:parent_index]]['type']
        case f['type']
            when "section"
                collection.pop if (collection[-1] && collection[-1][0..9] == "<section/>")
                collection << "<section/><tr class='b'><td class='b'><strong>#{f['title']}</strong></td><td class='b'></td><td class='b'></td></tr>"
            when "yesno"
                f['acceptance_value'] == -1 && collection << "<tr class='b'><td class='b'>#{f['title']}</td> #{TD_AA}NO#{TD_ZZ}<td class='b'>"
            when "range"
                f['value'].to_i <= 3        && collection << "<tr class='b'><td class='b'>#{f['title']}</td> #{TD_AA}#{f['value']}/5#{TD_ZZ}<td class='b'></td></tr>"
            when "image"
                if (!f['value'].empty? || f['notes'])
                    if f[:parent_id]
                        collection << "#{f['value'].count.to_s} photo(s)." + (f['notes'] ? "<br/>Notes: #{f['notes']}<br/>" : "")
                    else
                        collection << "<tr><td>#{f['title']}</td><td></td><td>#{f['value'].class == Array ? f['value'].count : '0'} photo(s)." +
                                      (f['notes'] ? "<br/>Notes: #{f['notes']} </td>" : "</td>")
                        collection[-1] && !f['next_field_parent_id'] && collection[-1] << "</tr>"
                    end
                end
            when "text"
                if !f['value'].empty?
                    if f[:parent_id]
                        collection << "#{f['title']}: #{f['value']}"
                    else
                        collection << "<tr><td>#{f['title']}</td><td> </td><td>#{f['value']}</td>"
                        collection[-1] && !f['next_field_parent_id'] && collection[-1] << "</tr>"
                    end
                end
        end
        # if !f[:next_id] && !collection.empty? then collection[-1] << "<!--end of form data-->" end
    }
    if collection.empty? then collection << "<tr><td>No problems were found.<td></tr>" end # unlikely?, but let's not have empty array here.
    collection
end

# filename/path chunks...
# 1 chonk = 46,656 permutations; 2 chonks = 2,176,782,336.
def chonk(num=1)
    chonker = ""
    num.times { |n| 
        chonker << [*('a'..'z'),*('0'..'9')].shuffle[0,3].join
        (num > 1 && n+1 < num) && chonker << "-"
    }
    chonker
end

# Use to make a page... also handy if wer want to make short, type-able photo links?
def create_redirects(redirects)
    redirects.each { |link| redirects[chonk + '-' + chonk] = link }
end

def send_mail(sender = DEFAULT_SENDER,
              subject = DEFAULT_SUBJECT,
              recipient = ALERT_RECIPIENT,
              msg = DEFAULT_MESSAGE)
    content = Content.new(type: 'text/html', value: msg)
    mail = Mail.new(Email.new(email: sender), subject, Email.new(email: recipient), content)
    sg = SendGrid::API.new(api_key: ENV['SENDGRID_API_KEY'])
    response = sg.client.mail._('send').post(request_body: mail.to_json)
    log(". Send mail:
        . from: #{sender} to: #{recipient} subject: #{subject}
        . Returned: #{response.status_code}")
end

def log(msg)
    if (LOGGING == true)
        puts "
        ** #{Time.now.inspect} **
        #{msg}
        -- end --"
    end
end

def squawk(summary = 'Lambda error.',
           err = 'Unknown error happened in Zenput digest lambda (AWS).',
           suppress = false)
    log(err)
    if (ALERT == true && suppress == false)
        send_mail(DEFAULT_SENDER, summary, ALERT_RECIPIENT, err)
    end
    raise "Squawk!"
end