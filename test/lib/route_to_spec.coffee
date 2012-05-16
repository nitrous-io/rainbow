routeTo = require '../../app/lib/route_to'
BaseController = require '../../app/lib/base_controller'

describe 'routeTo(controllerClass, action)', ->
  [fn, controllerClass] = []

  before ->
    controllerClass = sinon.spy(BaseController)
    fn = routeTo(controllerClass, 'index')

  it 'returns a function', ->
    fn.should.be.a 'function'

  context 'running the function', ->
    [req, res, controller] = []

    before ->
      req = sinon.stub()
      res = sinon.stub()
      controller = sinon.mock(BaseController.prototype)

    it 'initializes the controller', ->
      fn(req, res)
      controllerClass.calledWithNew().should.be.true
      controllerClass.calledWithExactly(req, res).should.be.true

    it 'invokes the action', ->
      controller.expects('index').once()
      fn(req, res)
      controller.verify()

