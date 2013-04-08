BoxUser = require '../../app/models/box_user'
BaseModel = require('action-base').BaseModel

describe 'BoxUser', ->
  it 'is a subclass of BaseModel', ->
    expect(new BoxUser).to.be.an.instanceof BaseModel

  its 'tableName property is defined', ->
    expect(BoxUser.tableName).to.equal 'box_users'
