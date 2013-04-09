EventEmitter = require('events').EventEmitter

module.exports = class BaseSocket extends EventEmitter
  namespace: 'base'

  constructor: (@connection) ->
    this.initialize()

  initialize: ->

  destroy: ->

  send: (event, args...) ->
    @connection.send [@namespace, event, args]

