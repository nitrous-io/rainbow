process.env.NODE_ENV = 'test'

global.context = describe
global.specify = it

global.sinon = require 'sinon'
global.assert = require 'should'
global.expect = require 'expect.js'

require './support/include_object_matcher'

app = require '../app'
app.listen 8888

global.Factory = require './factories'

