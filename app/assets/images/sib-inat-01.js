$(".bg-collapse").click(function(){
  $(".dashboard-content-wrapper").toggleClass("collapse-sidebar");
  $(".bg-collapse").toggleClass("collapsed-menu");
  $(".active").toggleClass("active-menu");
});

$('.main-sidebar li').hover(
  function () {
    if (!$(this).hasClass("active-menu")) {
      $('ul', this).fadeIn();
    }
  },
  function () {
    if (!$(this).hasClass("active-menu")) {
      $('ul', this).fadeOut();
    }
  }
);

function docwidth() {
  var winsize = $( window ).width();
  var setwidth = 700;
  
  if(winsize < setwidth) {
    $(".dashboard-content-wrapper").addClass("collapse-sidebar");
    $(".bg-collapse").css("display", "none");
    $(".active").removeClass("active-menu");
  } else if (winsize > setwidth) {
    $(".dashboard-content-wrapper").removeClass("collapse-sidebar");
    $(".bg-collapse").css("display", "block");
    $(".active").addClass("active-menu");
  }
}

docwidth();

$(window).resize(docwidth);