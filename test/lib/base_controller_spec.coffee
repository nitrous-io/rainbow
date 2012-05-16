BaseController = require '../../app/lib/base_controller'
http = require 'http'
Request  = http.IncomingMessage
Response = http.ServerResponse

describe 'BaseController', ->
  [request, response, controller] = []

  before ->
    request = new Request()
    request.params =
      id: 'some-id'
      user_id: 'another-id'
    request.body =
      foo: 'bar'
      baz: 'qux'
    request.query =
      hello: 'world'
      humty: 'dumty'
    response = new Response(request)
    controller = new BaseController(request, response)

  it 'initializes properly', ->
    controller.request.should.equal request
    controller.response.should.equal response
    controller.params.should.eql
      id: 'some-id'
      user_id: 'another-id'
      foo: 'bar'
      baz: 'qux'
      hello: 'world'
      humty: 'dumty'

