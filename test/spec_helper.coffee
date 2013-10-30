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
process.env.DOWNLOADS_DIR = 'test/fixtures'

global.hasNoCacheHeaders = require './support/has_no_cache_headers'
global.hasCORSHeaders = require './support/has_cors_headers'
