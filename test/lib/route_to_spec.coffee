routeTo = require '../../app/lib/route_to'
BaseController = require '../../app/lib/base_controller'

describe 'routeTo(controllerClass, action)', ->
  fn = controllerClass = null

  before ->
    controllerClass = sinon.spy BaseController
    fn = routeTo controllerClass, 'index'

  it 'returns a function', ->
    expect(fn).to.be.a 'function'

  context 'running the function', ->
    req = res = controller = null

    before ->
      req = sinon.stub()
      res = sinon.stub()
      controller = sinon.mock BaseController.prototype

    it 'initializes the controller', ->
      fn req, res
      expect(controllerClass.calledWithNew()).to.be.true
      expect(controllerClass).to.have.been.calledWithExactly req, res

    it 'invokes the action', ->
      controller.expects('index').once()
      fn req, res
      controller.verify()

