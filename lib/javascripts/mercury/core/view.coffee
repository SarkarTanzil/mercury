#= require mercury/core/config
#= require mercury/core/events
#= require mercury/core/i18n
#= require mercury/core/logger
#= require mercury/core/module

class Mercury.View extends Mercury.Module
  @include Mercury.Config
  @include Mercury.Events
  @include Mercury.I18n
  @include Mercury.Logger

  @Modules: {}

  @logPrefix: 'Mercury.View:'

  @tag: 'div'

  eventSplitter: /^(\S+)\s*(.*)$/

  # The constructor will take any property of the options passed and assign them to instance variables. It creates the
  # base element, assigns attributes, and loads a template if one has been provided. Events and elements will be
  # inherited from the constructor unless provided at an instance level.
  #
  constructor: (@options = {}) ->
    @[key] = value for key, value of @options

    @buildElement()

    @elements = $.extend({}, @constructor.elements, @elements)
    @events = $.extend({}, @constructor.events, @events)
    @attributes = $.extend({}, @constructor.attributes, @attributes)

    @refreshElements()

    @build?()                                              # call build if it's defined
    @trigger('build')                                      # trigger the build event

    @delegateEvents(@events)
    @refreshElements()

    super
    @trigger('init')


  # Builds the element that this view will use -- unless one is already defined. This method can be overridden to create
  # your own element, or add additional functionality to the initial build process.
  #
  buildElement: ->
    if @$el
      @el = @$el.get(0)
    else
      @el = document.createElement(@tag || @constructor.tag) unless @el
      @$el = $(@el)
    @attr(@attributes)
    @addClass(@constructor.className)
    @addClass(@className)
    @html(@renderTemplate(@template || @constructor.template)) if @template || @constructor.template


  # Delegates to jQuery find. Simplifies scoped finds within our own element.
  #
  $: (selector) ->
    $(selector, @$el)


  # Delegates to jQuery addClass.
  #
  addClass: (className) ->
    @$el.addClass(className)


  # Delegates to jQuery removeClass.
  #
  removeClass: (className) ->
    @$el.removeClass(className)


  # Delegate to jQuery attr.
  #
  attr: (key, value) ->
    return @$el.attr(key) if key && arguments.length == 1
    @$el.attr(key, value)


  # Delegate to jQuery css.
  #
  css: (key, value) ->
    return @$el.css(key) if key && arguments.length == 1
    @$el.css(key, value)


  # Sets the html of our element and re-finds any elements that we're actively tracking.
  # Returns el for chaining, or contents if no arguments.
  #
  html: (element) ->
    return @$el.html() unless arguments.length
    @$el.html(element?.$el || element?.el || element)
    @refreshElements()
    @$el


  # Append an element, elements, or view(s). Accepts a list of elements or views, and re-finds any elements we're
  # actively tracking after appending them.
  # Returns el for chaining.
  #
  append: (elements...) ->
    elements = (e.$el || e.el || e for e in elements)
    @$el.append(elements...)
    @refreshElements()
    @$el


  # Append this view to another element or view.
  # Returns el for chaining.
  #
  appendTo: (element) ->
    @$el.appendTo(element.$el || element.el || element)
    @$el


  # Delegates to setTimeout swapping the argument order, and calling the callback within our scope.
  # Returns the setTimeout so it can be cancelled.
  #
  delay: (ms, callback) ->
    setTimeout((=> callback.call(@)), ms)


  # Finds elements and assigns them to instance variables. Uses the items defined in @elements for assigning instance
  # variables to resolved elements.
  #
  refreshElements: ->
    @["$#{key}"] = @$(value) for key, value of @elements


  # Renders a template as a function or string. Looks in JST for the path provided (prefixed with /mercury/templates/),
  # and will fall back to requesting the content from the server if enabled.
  # Returns the contents of the rendered template.
  #
  renderTemplate: (path, options = null) ->
    template = JST["/mercury/templates/#{path}"]
    template = @fetchTemplate(path) if @config('templates:enabled') && !template
    return template.call(options || @) if typeof(template) == 'function'
    template


  # Makes an synchronous ajax request to the server for template content, which allows for fallbacks to be provided if
  # they don't exist in JST.
  # Returns whatever content the server responded with.
  #
  fetchTemplate: (path) ->
    template = null
    $.ajax
      url: [@config('templates:prefixUrl'), path].join('/')
      async: false
      success: (content) -> template = content
    template


  # When setting content or refreshing elements you may want to focus the first element that's focusable. This will
  # find the first element with a positive tab index that's visile and call focus on it.
  #
  focusFirstFocusable: ->
    @$(':input:visible[tabindex != "-1"]')[0]?.focus()


  # Standard event handler that will prevent an event, and optionally stop it from propagating.
  #
  prevent: (e, stop = false) ->
    return unless e && e.preventDefault
    e.preventDefault()
    e.stopPropagation() if stop


  # Releases the instance and triggers a release event. Releasing a view removes the element from the DOM, and removes
  # all event listeners including those that have been added externally.
  #
  release: ->
    @trigger('release')
    @$el.remove()
    Mercury.off(name, method) for name, method of @__global_handlers__ || {}
    @off()


  # Resolve events to methods, callbacks or global events.
  #
  # Element Events.
  # 'click': function() { }                      // call callback when top level element (this.el) is clicked.
  # 'click .about': 'displayAbout'               // call this.displayAbout when <div class="about"> is clicked.
  #
  # Global Events.
  # 'mercury:action': 'handleAction'             // call this.handleAction on the global 'action' event.
  # 'click': 'mercury:hide'                      // triggers a global 'hide' event with this.el is clicked.
  #
  delegateEvents: (el, events) ->
    if arguments.length == 1
      events = el
      el = @$el

    @__global_handlers__ ||= {}
    for key, method of events

      if typeof(method) == 'function'
        method = do (method) => =>
          method.apply(@, arguments)
          true # always return true from event handlers
      else
        if method.indexOf('mercury:') == 0 # trigger global event
          method = method.replace(/^mercury:/, '')
          method = do (method) => =>
            Mercury.trigger(method, @)
            true
        else unless @[method]
          throw new Error("#{method} doesn't exist")
        else
          method = do (method) => =>
            @[method].apply(@, arguments)
            true

      if key.indexOf('mercury:') == 0 # bind to global event
        key = key.replace(/^mercury:/, '')
        @__global_handlers__[key] = method
        Mercury.on(key, method)
        continue

      [match, event, selector] = key.match(@eventSplitter)
      el.on(event, selector || null, method)
