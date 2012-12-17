Fixture = require './support/fixture'
global.sinon = require 'sinon'
global.chai = require 'chai'
global.request = require 'supertest'
sinonChai = require 'sinon-chai'

process.env.NODE_ENV = 'test'
process.env.SECRET_TOKEN = 'secret_token'

global.context = global.describe
global.xcontext = global.xdescribe
global.specify = global.it
global.xspecify = global.xit
global.its = global.it
global.xits = global.xit
global.should = global.chai.should()
global.expect = global.chai.expect
global.assert = global.chai.assert
global.chai.use sinonChai

before (done) -> Fixture.setup done
after (done) -> Fixture.flush done
