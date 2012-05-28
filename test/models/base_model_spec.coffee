BaseModel = require '../../app/models/base_model'
pg = require('pg').native

describe 'BaseModel', ->
  describe '.findOne', ->
    context 'when tableName property is defined', ->
      pgConnectStub = null

      before (done) ->
        pg.connect (err, client) ->
          throw err if err
          client.query "CREATE TABLE \"test_table\" (
            id integer PRIMARY KEY,
            foo varchar(255),
            bar integer
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
          BaseModel.findOne 'id = $1', [123], (err, model) ->
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
            BaseModel.findOne 'id = $1', [123], (err, model) ->
              err.should.equal error
              expect(model).to.be null
              done()

        context 'when a row with a given id does not exist', ->
          it 'returns a null object', (done) ->
            BaseModel.findOne 'id = $1', [123], (err, model) ->
              expect(err).to.be null
              expect(model).to.be null
              done()

        context 'when a row with a given id exists', ->
          before (done) ->
            pg.connect (err, client) ->
              throw err if err
              client.query 'INSERT INTO "test_table" (id, foo, bar) VALUES ($1, $2, $3)', [123, 'test', 42], (err, res) ->
                throw err if err
                done()

          after (done) ->
            pg.connect (err, client) ->
              throw err if err
              client.query 'DELETE FROM "test_table" WHERE id = $1', [123], (err, res) ->
                throw err if err
                done()

          context 'when columns are not specified', ->
            it 'fetches a row with given id and returns a model object with all attributes', (done) ->
              BaseModel.findOne 'id = $1', [123], (err, model) ->
                model.should.be.an.instanceof BaseModel
                model.id.should.equal 123
                model.foo.should.equal 'test'
                model.bar.should.equal 42
                done()

          context 'when columns are specified', ->
            it 'fetches a row with given id and returns a model object with specified attributes', (done) ->
              BaseModel.findOne 'id = $1', [123], ['id', 'foo'], (err, model) ->
                model.should.be.an.instanceof BaseModel
                model.id.should.equal 123
                model.foo.should.equal 'test'
                model.should.not.have.property 'bar'
                done()

    context 'when tableName property is not defined', ->
      beforeEach ->
        delete BaseModel.tableName

      it 'calls callback with error', (done) ->
        BaseModel.findOne 'id = $1', [123], (err, model) ->
          err.should.be.an.instanceof Error
          err.message.should.match /tableName/
          expect(model).to.be null
          done()

  describe '.findById', ->
    findOneStub = cbSpy = null

    beforeEach ->
      findOneStub = sinon.stub BaseModel, 'findOne'
      cbSpy = sinon.spy()

    afterEach ->
      findOneStub.restore()

    context 'when columns option is given', ->
      it 'selects selected columns only', ->
        BaseModel.findById(123, ['foo', 'bar'], cbSpy)
        findOneStub.calledWith('id = $1', [123], ['foo', 'bar'], cbSpy).should.be.true

    context 'when columns option is not given', ->
      it 'selects all columns (*)', ->
        BaseModel.findById(123, cbSpy)
        findOneStub.calledWith('id = $1', [123], cbSpy).should.be.true

