require "rubygems"
require_relative 'lambda'
require_relative 'keys'

event = {"body"=>{'form-id': FORM_ID, 'options': ['browser']}.to_json}

__test(event)
# puts fetch_form(FORM_ID).to_json