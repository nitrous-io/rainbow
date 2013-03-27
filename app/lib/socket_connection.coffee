_ = require 'underscore'

module.exports = class SocketConnection
  constructor: (@ws) ->
    @sockClasses = {}
    @socks = {}
    @ws.on 'data',  _.bind(@_onData, this)
    @ws.on 'close', _.bind(@_onClose, this)

  register: (sockClass) ->
    @sockClasses[sockClass::namespace] = sockClass

  close: ->
    @ws.close()

  send: (payload) ->
    @ws.write JSON.stringify(payload)

  _onData: (message) ->
    try
      message = JSON.parse(message)
    catch err
      return
    return unless message instanceof Array

    [namespace, event, args, callbackId] = message

    if event == 'init'
      if sockClass = @sockClasses[namespace]
        @socks[namespace] = new sockClass this
        if callbackId?
          this._invokeCallback callbackId, []
    else if sock = @socks[namespace]
      args.unshift event
      if callbackId?
        args.push =>
          this._invokeCallback callbackId, _.toArray(arguments)...
      sock.emit args...

  _onClose: ->
    @sockClasses = null
    @socks = null

  _invokeCallback: (callbackId, args) ->
    @ws.write JSON.stringify(['global', 'callback', [callbackId, args]])

