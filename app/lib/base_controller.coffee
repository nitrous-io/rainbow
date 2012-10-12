module.exports = class BaseController
  constructor: (@request, @response) ->
    @app = @request.app
    @params = {}
    if @request
      ['query', 'body', 'params'].forEach (p) =>
        if @request.hasOwnProperty(p)
          @params[key] = value for own key, value of @request[p]

  index: ->

