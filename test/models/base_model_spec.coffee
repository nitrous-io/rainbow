BaseModel = require '../../app/models/base_model'
pg = require('pg').native

describe 'BaseModel', ->
  describe '.findById', ->
    context 'when tableName property is defined', ->
      pgConnectStub = null

      before (done) ->
        pg.connect (err, client) ->
          throw err if err
          client.query "CREATE TABLE \"test_table\" (
            id integer PRIMARY KEY,
            foo varchar(255)
          )", (err, res) ->
            throw err if err
            done()

      after (done) ->
        pg.connect (err, client) ->
          throw err if err
          client.query 'DROP TABLE "test_table"', (err, res) ->
            throw err if err
            done()

      beforeEach ->
        BaseModel.tableName = 'test_table'

      context 'when pg.connect fails', ->
        error = null

        beforeEach ->
          error = new Error
          pgConnectStub = sinon.stub pg, 'connect', (cb) ->
            cb(error, null)

        afterEach ->
          pgConnectStub.restore()

        it 'calls callback with error', (done) ->
          BaseModel.findById 123, (err, model) ->
            err.should.equal error
            expect(model).to.be null
            done()

      context 'when pg.connect is successful', ->
        context 'when query fails with error', ->
          fakeClient = error = null

          beforeEach ->
            error = new Error
            fakeClient = { query: -> }
            sinon.stub fakeClient, 'query', (q, v, cb) ->
              cb(error, null)
            pgConnectStub = sinon.stub pg, 'connect', (cb) ->
              cb(null, fakeClient)

          afterEach ->
            pgConnectStub.restore()

          it 'calls callback with error', (done) ->
            BaseModel.findById 123, (err, model) ->
              err.should.equal error
              expect(model).to.be null
              done()

        context 'when a row with a given id does not exist', ->
          it 'returns a null object', (done) ->
            BaseModel.findById 123, (err, model) ->
              expect(model).to.be null
              done()

        context 'when a row with a given id exists', ->
          before (done) ->
            pg.connect (err, client) ->
              throw err if err
              client.query 'INSERT INTO "test_table" (id, foo) VALUES ($1, $2)', [123, 'bar'], (err, res) ->
                throw err if err
                done()

          after (done) ->
            pg.connect (err, client) ->
              throw err if err
              client.query 'DELETE FROM "test_table" WHERE id = $1', [123], (err, res) ->
                throw err if err
                done()

          it 'fetches a row with given id and returns a model object with the attributes', (done) ->
            BaseModel.findById 123, (err, model) ->
              model.should.be.an.instanceof BaseModel
              model.id.should.equal 123
              model.foo.should.equal 'bar'
              done()

    context 'when tableName property is not defined', ->
      beforeEach ->
        delete BaseModel.tableName

      it 'calls callback with error', (done) ->
        BaseModel.findById 123, (err, model) ->
          err.should.be.an.instanceof Error
          err.message.should.match /tableName/
          expect(model).to.be null
          done()

