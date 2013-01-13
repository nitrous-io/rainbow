_ = require 'underscore'

process.env.NODE_ENV = 'test'

global.context = global.describe
global.xcontext = global.xdescribe
global.specify = global.it
global.xspecify = global.xit
global.its = global.it
global.xits = global.xit

global.sinon = require 'sinon'
global.chai = require 'chai'
global.request = require 'supertest'
sinonChai = require 'sinon-chai'
global.should = global.chai.should()
global.expect = global.chai.expect
global.assert = global.chai.assert
global.chai.use sinonChai

process.env.SECRET_TOKEN = 'secret_token'

# accepts either callback or done, callback
# arguments will be called in reversed orders when nextTick triggered
# Example
#   asyncDone -> console.log "HERE"
#   asyncDone done, -> console.log "HERE"
global.asyncDone = ->
  args = _.values arguments
  process.nextTick -> func() for func in args.reverse()

# create a sanbox to ease the creation/restoration of fakes
global.sandbox = sinon.sandbox.create()
afterEach -> global.sandbox.restore()
