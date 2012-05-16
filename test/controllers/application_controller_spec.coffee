ApplicationController = require '../../app/controllers/application_controller'
BaseController = require '../../app/lib/base_controller'
http = require 'http'
Request  = http.IncomingMessage
Response = http.ServerResponse
async = require 'async'

describe 'ApplicationController', ->
  [request, response, controller] = []

  beforeEach (done) ->
    request = new Request()
    response = new Response(request)
    controller = new ApplicationController(request, response)
    done()

  it 'is a subclass of BaseController', ->
    (controller instanceof BaseController).should.be.true

