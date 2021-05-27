---
# Jekyll front matter needed to trigger coffee compilation
---
# Search Box Element
# =============================================================================
# Programmatically add the search box to the site
# This allows the search box to be hidden if javascript is disabled
siteNavElement = document.getElementsByClassName("site-nav")[0]
siteSearchElement = document.createElement("div")
siteSearchElement.classList.add("site-search")
siteSearchElement.innerHTML = """
<svg class="search-icon" viewBox="0 0 18 18" width="18" height="18">
  <path ill="#222222" d="M12.43 11.73C13.41 10.59 14 9.11 14 7.5 14 3.91 11.09 1 7.5 1S1 3.91 1 7.5 3.91 14 7.5 14c1.61 0 3.09-.59 4.23-1.57l.7-.7zM7.5 12C5.01 12 3 9.99 3 7.5S5.01 3 7.5 3 12 5.01 12 7.5 9.99 12 7.5 12z"/>
  <path fill="#222222" d="M12.41293 11l4.7982 4.79818-1.41423 1.41422L11 12.39863"/>
</svg>
"""
clearButton = document.createElement("label");
clearButton.classList.add("clear-button");
clearButton.innerHTML = """
<svg class="clear-icon" viewBox="0 0 18 18" width="18" height="18">
  <path d="M2.42755 1L17.0331 15.60554l-1.41423 1.4142L1 2.38402"/>
  <path d="M1 15.51932L15.51933 1l1.4142 1.4142L2.2978 17.0331"/>
</svg>
"""
searchBoxElement = document.createElement("input")
searchBoxElement.id = "search-box"
searchBoxElement.setAttribute("type", "text")
searchBoxElement.setAttribute("placeholder", "Building search index...")
searchBoxElement.setAttribute("disabled", "")
siteSearchElement.prepend(clearButton)
siteSearchElement.prepend(searchBoxElement)
siteNavElement.prepend(siteSearchElement)
clearButton.onclick = ->
  searchBoxElement.value = ""
  searchBoxElement.dispatchEvent(new Event('input', {
    'bubbles': true
    'cancelable': true
  }))

searchBoxElement.oninput = (event) ->
  if searchBoxElement.value.length > 0
    siteSearchElement.classList.add "filled"
  else
    siteSearchElement.classList.remove "filled"


# Data Blob
# =============================================================================
# The main "blob" of site data constructed by liquid
# We cherry pick to minimize size
# Also because jsonify doesn't work quite right and collapses the page objects
# into just strings when we jsonify the whole site
site =
  title: {{ site.title | jsonify }}
  url: {{ site.url | jsonify }}
pages = [
  {% for site_page in site.html_pages %}
    {
      "title": {{ site_page.title | jsonify }},
      # For consistency all page markdown is converted to HTML
      {% if site_page.url == page.url %}
      "content": {{ site_page.content | jsonify }},
      {% else %}
      "content": {{ site_page.content | markdownify | jsonify }},
      {% endif %}
      "url": {{ site_page.url | relative_url | jsonify }}
    }
  {% endfor %}
]
pageIndex = {}
pageOrder = [
  {% for section_title in site.section_order %}
    {{ section_title | jsonify }}
  {% endfor %}
]

if pageOrder.length > 0
  pages.sort (a, b) -> return if pageOrder.indexOf(a.title) < pageOrder.indexOf(b.title) then -1 else 1

pages.forEach (page) -> pageIndex[page.url] = page


# Site Hierarchy
# =============================================================================
# Helper function which returns a flat list of header and text nodes
HEADER_TAGS = ["H1", "H2", "H3", "H4", "H5", "H6"]
getHeadersAndText = (root)->
  walker = document.createTreeWalker(
    root
    NodeFilter.SHOW_ALL
    acceptNode: (node)->
      # Grab header tags for building a table of contents
      if HEADER_TAGS.indexOf(node.tagName) >= 0
        return NodeFilter.FILTER_ACCEPT
      # Reject the immediate children of header tags
      # Since they are already included under their parent
      if HEADER_TAGS.indexOf(node.parentNode.tagName) >= 0
        return NodeFilter.FILTER_REJECT
      # Add basic text nodes inbetween headers
      if node.nodeType is 3 then return NodeFilter.FILTER_ACCEPT
      # Skip everything else
      return NodeFilter.FILTER_SKIP
    false
  )
  nodes = []
  while node = walker.nextNode() then nodes.push node
  return nodes


# Build a site hierarchy tree of nested sections
# Each section has a representative component
# An array of its own text
# and an array of subsections
siteHierarchy = {
  component: site
  title: site.title
  url: site.url
  text: []
}
# Parse page html and build a section hierarchy per page
siteHierarchy.subsections = pages.map (page) ->
  body = new DOMParser().parseFromString(page.content, 'text/html').body
  headersAndText = getHeadersAndText(body)
  root =
    parent: siteHierarchy
    component: page
    title: page.title
    url: page.url
    text: [] # Will be converted into a single string later
    subsections: []
  # Iterate through the html nodes and build the section tree depth first
  currentSection = root
  headersAndText.forEach (node) ->
    # Text nodes get added under the current header
    if HEADER_TAGS.indexOf(node.tagName) < 0
      currentSection.text.push node.textContent
      return
    # If you're bigger then climb the tree till you're not
    # Then add yourself and drill down
    # #lifeprotips
    while (
      HEADER_TAGS.indexOf(node.tagName) <=
      HEADER_TAGS.indexOf(currentSection.component.tagName)
    ) then currentSection = currentSection.parent
    newSection =
      parent: currentSection
      component: node
      title: node.textContent
      url: page.url + "#" + node.id
      text: []
      subsections: []
    currentSection.subsections.push newSection
    currentSection = newSection
  return root

# Bake in each section's text into a single string
queue = [siteHierarchy]
while queue.length > 0
  section = queue.shift()
  section.text = section.text.join('').trim()
  queue.push.apply queue, section.subsections

# Compress the tree by merging redundant sections
# Defined as sections with no text of their own and only 1 sub section
queue = [siteHierarchy]
while queue.length > 0
  section = queue.shift()
  # Contract
  # The parent section effectively consumes the child
  # And gains the power of TWO sections a la Cell and Android 18
  while section.subsections.length == 1 and section.text.length == 0
    section.text += section.subsections[0].text
    section.subsections = section.subsections[0].subsections
    section.subsections.forEach (child) -> child.parent = section
  queue.push.apply queue, section.subsections

# Build an index to easily retrive sections by url
sectionIndex = {}
stack = [siteHierarchy]
while stack.length > 0
  section = stack.pop()
  stack.push.apply(stack, section.subsections.slice().reverse())
  sectionIndex[section.url] = section

# Asynchronously build the search index by spawning a web worker
# Build a serializable array for sending to workers
serializableSiteSections = Object.values(sectionIndex).map (section) ->
  serializableSection = Object.assign({}, section)
  delete serializableSection.parent
  delete serializableSection.component
  delete serializableSection.subsections
  return serializableSection
searchIndexPromise = new Promise (resolve, reject) ->
  worker = new Worker("{{ '/assets/worker.js' | relative_url }}")
  worker.onmessage = (event) ->
    worker.terminate()
    resolve lunr.Index.load event.data
  worker.onerror = (error) ->
    Promise.reject(error)
  worker.postMessage serializableSiteSections

# Search
# =============================================================================
# Helper function to translate lunr search results
# Returns a simple {title, description, link} array
snippetSpace = 40
maxSnippets = 4
maxResults = 10
translateLunrResults = (lunrResults) ->
  lunrResults.slice(0, maxResults);
  return lunrResults.map (result) ->
    matchedDocument = sectionIndex[result.ref]
    snippets = [];
    # Loop over matching terms
    for term of result.matchData.metadata
      # Loop over the matching fields for each term
      fields = result.matchData.metadata[term]
      for field of fields
        positions = fields[field].position
        positions = positions.slice(0, 3)
        # Loop over the position within each field
        for positionIndex of positions
          position = positions[positionIndex]
          # Add to the description the snippet for that match
          preMatch = matchedDocument[field].substring(
            position[0] - snippetSpace,
            position[0]
          )
          match = matchedDocument[field].substring(
            position[0],
            position[0] + position[1]
          )
          postMatch = matchedDocument[field].substring(
            position[0] + position[1],
            position[0] + position[1] + snippetSpace
          )
          snippet = '...' + preMatch + '<strong>' + match + '</strong>' + postMatch + '...  '
          snippets.push snippet
          if (snippets.length >= maxSnippets) then break
        if (snippets.length >= maxSnippets) then break
      if (snippets.length >= maxSnippets) then break
    # Build a simple flat object per lunr result
    return {
      title: matchedDocument.title
      description: snippets.join('');
      url: matchedDocument.url
    }


# Displays the search results in HTML
# Takes an array of objects with "title" and "description" properties
renderSearchResults = (searchResults) ->
  container = document.getElementsByClassName('search-results')[0]
  container.innerHTML = ''
  searchResults.forEach (result) ->
    element = document.createElement('a')
    element.classList.add 'nav-link'
    element.setAttribute 'href', result.url
    element.innerHTML = result.title
    description = document.createElement('p')
    description.innerHTML = result.description
    element.appendChild description
    container.appendChild element
    return
  return


# Enable the searchbox once the index is built
searchIndexPromise.then (searchIndex) ->
  searchBoxElement.removeAttribute "disabled"
  searchBoxElement.setAttribute "placeholder", "Type here to search..."
  searchBoxElement.addEventListener 'input', (event) ->
    toc = document.getElementsByClassName('table-of-contents')[0]
    searchResults = document.getElementsByClassName('search-results')[0]
    query = searchBoxElement.value
    if query.length == 0
      searchResults.setAttribute 'hidden', true
      toc.removeAttribute 'hidden'
    else
      toc.setAttribute 'hidden', ''
      searchResults.removeAttribute 'hidden'
      lunrResults = searchIndex.search(query + "~1")
      results = translateLunrResults(lunrResults)
      renderSearchResults results

# Table of Contents
# =============================================================================
# Table of contents rendering
tocElement = document.getElementsByClassName("table-of-contents")[0]
tocElement.innerHTML = ""
buildNav = (section) ->
  navBranch = document.createElement('div')
  navBranch.classList.add('nav-branch')
  if section.subsections.length > 0
    expandButton = document.createElement('div');
    expandButton.classList.add('expand-button')
    expandButton.onclick = (event) -> navBranch.classList.toggle("expanded")
    navBranch.appendChild expandButton
  navLinkElement = document.createElement('a')
  navLinkElement.classList.add('nav-link')
  navLinkElement.setAttribute('href', section.url)
  navLinkElement.innerHTML = section.title
  navBranch.appendChild(navLinkElement)
  section.subsections.forEach (section) ->
    navBranch.appendChild(buildNav(section))
  return navBranch
siteHierarchy.subsections.forEach (section) ->
  tocElement.appendChild(buildNav(section))

# HTML5 History
# =============================================================================
# Setup HTML 5 history for single page goodness
main = document.getElementsByTagName("main")[0]
menuToggle = document.getElementById("menu-toggle")
document.body.addEventListener("click", (event) ->
  # Check if its within an anchor tag any any point
  # Traverse up its click tree and see if it affects any of them
  # If it does not find anything it just terminates as a null
  anchor = event.target
  while (anchor? and anchor.tagName isnt "A")
    anchor = anchor.parentNode
  if anchor? and anchor.host is window.location.host
    event.preventDefault()
    event.stopPropagation()
    # Need to hide the menu on mobile
    # On desktop this conveniently leaves it open which is intended behavior
    menuToggle.checked = false
    history.pushState(null, null, anchor.href)
    if anchor.hash.length > 0 then window.location = anchor.hash
    else window.location = "#"
, true)
# Map the popstate event
window.addEventListener "popstate", (event) ->
  page = pageIndex[window.location.pathname]
  # Only reflow the main content if necessary
  testBody = new DOMParser().parseFromString(page.content, "text/html").body;
  if main.innerHTML.trim() isnt testBody.innerHTML.trim()
    main.innerHTML = page.content
