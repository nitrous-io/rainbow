F = require '../support/fixture'
Box = require '../../app/models/box'
BaseModel = require('action-base').BaseModel
KeyPair = require '../../app/models/key_pair'
A = require 'async'

describe 'Box', ->
  it 'is a subclass of BaseModel', ->
    expect(new Box).to.be.an.instanceof BaseModel

  its 'tableName property is defined', ->
    expect(Box.tableName).to.equal 'boxes'

  describe '#findKeyPair', ->
    beforeEach (done) ->
      A.waterfall [
          (cb) -> F.flush cb
          (cb) -> F.box name: "aaaa", cb
          (@box_id, cb) => F.key_pair box_id: @box_id, cb
        ], (err, @key_pair_id) => done()

    afterEach (done) -> F.flush done

    it 'finds a key pair object for this box', (done) ->
      @box = new Box(id: @box_id)
      @box.findKeyPair (err, key_pair) =>
        expect(key_pair.box_id).to.eq(@box_id)
        expect(key_pair.public_key).to.eq("public-key")
        done()
