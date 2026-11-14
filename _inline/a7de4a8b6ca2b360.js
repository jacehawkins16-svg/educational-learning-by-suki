
(function () {
  var dismissed = false;
  try {
    dismissed = !!localStorage.getItem("hideFourthAndFifthBanner");
  } catch (e) {
    // localStorage blocked
  }
  var now = Date.now();
  var show =
    window.location.search.indexOf("showFourthAndFifthAnnouncement") !== -1 ||
    (!dismissed &&
      now > 1773633540000 &&
      now < 1794113940000);
  if (!show) {
    document.documentElement.classList.add("hide-fourth-and-fifth");
  }
})();
