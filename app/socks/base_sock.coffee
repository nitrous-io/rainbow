EventEmitter = require('events').EventEmitter

module.exports = class BaseSock extends EventEmitter
  namespace: 'base'

  constructor: (@connection) ->
    this.initialize()

  initialize: ->

  send: (event, args...) ->
    @connection.send [@namespace, event, args]

