(function() {
  var toggle = document.querySelector('.sidebar-toggle');
  var sidebar = document.getElementById('sidebar');

  if (toggle && sidebar) {
    toggle.addEventListener('click', function() {
      sidebar.classList.toggle('sidebar--open');
    });

    // Close sidebar when clicking a link (mobile)
    var links = sidebar.querySelectorAll('a');
    for (var i = 0; i < links.length; i++) {
      links[i].addEventListener('click', function() {
        sidebar.classList.remove('sidebar--open');
      });
    }
  }
})();
