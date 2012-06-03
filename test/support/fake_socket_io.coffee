EventEmitter = require('events').EventEmitter

module.exports = class FakeSocketIO extends EventEmitter
  constructor: ->
    @settings = {}
    @namespaces = {}
    @socket = new FakeSocket

  set: (key, value) ->
    @settings[key] = value

  of: (namespace) ->
    @namespaces[namespace] ||= new FakeSocketIO
    this

  authorization: (@authorizationHandler) ->
    this

class FakeSocket extends EventEmitter
  constructor: ->
    @handshake =
      data:
        user: { id: 123 }

