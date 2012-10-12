BaseController = require '../../app/lib/base_controller'
http = require 'http'
Request  = http.IncomingMessage
Response = http.ServerResponse

describe 'BaseController', ->
  request = response = controller = null

  before ->
    request = new Request()
    request.app =
      some: 'app'
    request.params =
      id: 'some-id'
      user_id: 'another-id'
    request.body =
      foo: 'bar'
      baz: 'qux'
    request.query =
      hello: 'world'
      humpty: 'dumpty'
    response = new Response request
    controller = new BaseController request, response

  it 'initializes properly', ->
    expect(controller.app).to.equal request.app
    expect(controller.request).to.equal request
    expect(controller.response).to.equal response
    expect(controller.params).to.deep.equal
      id: 'some-id'
      user_id: 'another-id'
      foo: 'bar'
      baz: 'qux'
      hello: 'world'
      humpty: 'dumpty'

