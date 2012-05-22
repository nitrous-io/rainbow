process.env.NODE_ENV = 'test'

global.context = global.describe
global.xcontext = global.xdescribe
global.specify = global.it
global.xspecify = global.xit
global.its = global.it
global.xits = global.xit

global.sinon = require 'sinon'
global.assert = require 'should'
global.expect = require 'expect.js'

require './support/include_object_matcher'

global.app = require '../app'
global.app.listen 8888

global.Factory = require './factories'

