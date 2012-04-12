$ = jQuery

if window? and window._gCalFlow_debug? and console?
  log = console
  log.debug ?= log.log
else
  log = {}
  log.error = log.warn = log.log = log.info = log.debug = ->

pad_zero = (num, size = 2) ->
  if 10 * (size-1) < num then return num
  ret = ""
  for i in [1..(size-"#{num}".length)]
    ret += "0"
  ret + num

class gCalFlow
  target: null
  template: $("""<div class="gCalFlow">
      <div class="gcf-header-block">
        <div class="gcf-title-block">
          <span class="gcf-title"></span>
        </div>
      </div>
      <div class="gcf-item-container-block">
        <div class="gcf-item-block">
          <div class="gcf-item-header-block">
            <div class="gcf-item-date-block">
              [<span class="gcf-item-date"></span>]
            </div>
            <div class="gcf-item-title-block">
              <strong class="gcf-item-title"></strong>
            </div>
          </div>
          <div class="gcf-item-body-block">
            <div class="gcf-item-description">
            </div>
          </div>
        </div>
      </div>
      <div class="gcf-last-update-block">
        LastUpdate: <span class="gcf-last-update"></span>
      </div>
    </div>""")
  opts: {
    maxitem: 15
    calid: null
    mode: 'upcoming'
    feed_url: null
    auto_scroll: true
    scroll_interval: 10 * 1000
    link_title: true
    link_item_title: true
    link_item_description: false
    link_target: '_blank'
    callback: null
    date_formatter: (d, allday_p) ->
      if allday_p
        return "#{d.getFullYear()}-#{pad_zero d.getMonth()+1}-#{pad_zero d.getDate()}"
      else
        return "#{d.getFullYear()}-#{pad_zero d.getMonth()+1}-#{pad_zero d.getDate()} #{pad_zero d.getHours()}:#{pad_zero d.getMinutes()}"
  }

  constructor: (target, opts) ->
    @target = target
    target.addClass('gCalFlow')
    if target.children().size() > 0
      log.debug "Target node has children, use target element as template."
      @template = target
    this.update_opts(opts)

  update_opts: (new_opts) ->
    log.debug "update_opts was called"
    log.debug "old options:", @opts
    @opts = $.extend({}, @opts, new_opts)
    log.debug "new options:", @opts

  gcal_url: ->
    if !@opts.calid && !@opts.feed_url
      log.error "Option calid and feed_url are missing. Abort URL generation"
      @target.text("Error: You need to set 'calid' or 'feed_url' option.")
      throw "gCalFlow: calid and feed_url missing"
    if @opts.feed_url
      @opts.feed_url
    else if @opts.mode == 'updates'
      "https://www.google.com/calendar/feeds/#{@opts.calid}/public/full?alt=json-in-script&max-results=#{@opts.maxitem}&orderby=lastmodified&sortorder=descending"
    else
      "https://www.google.com/calendar/feeds/#{@opts.calid}/public/full?alt=json-in-script&max-results=#{@opts.maxitem}&orderby=starttime&futureevents=true&sortorder=ascending&singleevents=true"

  fetch: ->
    log.debug "Starting ajax call for #{this.gcal_url()}"
    self = this
    success_handler = (data) ->
      log.debug "Ajax call success. Response data:", data
      self.render_data(data, this)
    $.ajax {
      success:  success_handler
      dataType: "jsonp"
      url: this.gcal_url()
    }

  parse_date: (dstr) ->
    di = Date.parse dstr
    if !di
      d = dstr.split('T')
      dinfo = $.merge d[0].split('-'), if d[1] then d[1].split(':')[0..1] else []
      eval "new Date(#{dinfo.join(',')});"
    else
      new Date(di)


  render_data: (data) ->
    log.debug "start rendering for data:", data
    feed = data.feed
    t = @template.clone()

    titlelink = @opts.titlelink ? "http://www.google.com/calendar/embed?src=#{@opts.calid}"
    if @opts.link_title
      t.find('.gcf-title').html $("<a />").attr({target: @opts.link_target, href: titlelink}).text feed.title.$t
    else
      t.find('.gcf-title').text feed.title.$t
    t.find('.gcf-link').attr {target: @opts.link_target, href: titlelink}
    t.find('.gcf-last-update').text @opts.date_formatter this.parse_date feed.updated.$t

    it = t.find('.gcf-item-block')
    it.detach()
    it = $(it[0])
    log.debug "item block template:", it
    items = $()
    log.debug "render entries:", feed.entry
    for ent in feed.entry[0..@opts.maxitem]
      log.debug "formatting entry:", ent
      ci = it.clone()
      if ent.gd$when
        st = ent.gd$when[0].startTime
        stf = @opts.date_formatter this.parse_date(st), st.indexOf('T') < 0
        ci.find('.gcf-item-date').text stf
        ci.find('.gcf-item-start-date').text stf
        et = ent.gd$when[0].endTime
        etf = @opts.date_formatter this.parse_date(et), et.indexOf('T') < 0
        ci.find('.gcf-item-end-date').text etf
      ci.find('.gcf-item-update-date').text @opts.date_formatter this.parse_date(ent.updated.$t), false
      link = $('<a />').attr {target: @opts.link_target, href: ent.link[0].href}
      if @opts.link_item_title
        ci.find('.gcf-item-title').html link.clone().text ent.title.$t
      else
        ci.find('.gcf-item-title').text ent.title.$t
      if @opts.link_item_description
        ci.find('.gcf-item-description').html link.clone().text ent.content.$t
      else
        ci.find('.gcf-item-description').text ent.content.$t
      ci.find('.gcf-item-link').attr {href: ent.link[0].href}
      log.debug "formatted item entry:", ci[0]
      items.push ci[0]

    log.debug "formatted item entry array:", items
    ic = t.find('.gcf-item-container-block')
    log.debug "item container element:", ic
    ic.html(items)

    @target.html(t.html())
    this.bind_scroll()
    @opts.callback.apply(@target) if @opts.callback

  bind_scroll: ->
    scroll_container = @target.find('.gcf-item-container-block')
    scroll_children = scroll_container.find(".gcf-item-block")
    log.debug "scroll container:", scroll_container
    if not @opts.auto_scroll or scroll_container.size() < 1 or scroll_children.size() < 2
      return
    state = {idx: 0}
    scroller = ->
      log.debug "current scroll position:", scroll_container.scrollTop()
      log.debug "scroll capacity:", scroll_container[0].scrollHeight - scroll_container[0].clientHeight
      if typeof scroll_children[state.idx] is 'undefined' or scroll_container.scrollTop() >= scroll_container[0].scrollHeight - scroll_container[0].clientHeight
        log.debug "scroll to top"
        state.idx = 0
        scroll_container.animate {scrollTop: scroll_children[0].offsetTop}
      else
        scroll_to = scroll_children[state.idx].offsetTop
        log.debug "scroll to #{scroll_to}px"
        scroll_container.animate {scrollTop: scroll_to}
        state.idx += 1
    scroll_timer = setInterval scroller, @opts.scroll_interval

methods =
  init: (opts = {}) ->
    data = this.data('gCalFlow')
    if !data then this.data 'gCalFlow', { target: this, obj: new gCalFlow(this, opts) }

  destroy: ->
    data = this.data('gCalFlow')
    data.obj.target = null
    $(window).unbind('.gCalFlow')
    data.gCalFlow.remove()
    this.removeData('gCalFlow')

  render: ->
    data = this.data('gCalFlow')
    self = data.obj
    self.fetch()

      
$.fn.gCalFlow = (method) ->
  orig_args = arguments
  if typeof method == 'object' || !method
    this.each ->
      methods.init.apply $(this), orig_args
      methods.render.apply $(this), orig_args
  else if methods[method]
    this.each ->
      methods[method].apply $(this), Array.prototype.slice.call(orig_args, 1)
  else if method == 'version'
    "1.0.1"
  else
    $.error "Method #{method} dose not exist on jQuery.gCalFlow"

# vim: set sts=2 sw=2 expandtab: