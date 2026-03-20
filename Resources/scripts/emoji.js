(function() {
  var map = {
    '+1':'\uD83D\uDC4D','-1':'\uD83D\uDC4E','100':'\uD83D\uDCAF','1234':'\uD83D\uDD22',
    'smile':'\uD83D\uDE04','laughing':'\uD83D\uDE06','blush':'\uD83D\uDE0A','smiley':'\uD83D\uDE03',
    'relaxed':'\u263A\uFE0F','smirk':'\uD83D\uDE0F','heart_eyes':'\uD83D\uDE0D','kissing_heart':'\uD83D\uDE18',
    'kissing':'\uD83D\uDE17','wink':'\uD83D\uDE09','stuck_out_tongue_winking_eye':'\uD83D\uDE1C',
    'stuck_out_tongue':'\uD83D\uDE1B','flushed':'\uD83D\uDE33','grin':'\uD83D\uDE01',
    'pensive':'\uD83D\uDE14','relieved':'\uD83D\uDE0C','unamused':'\uD83D\uDE12',
    'disappointed':'\uD83D\uDE1E','persevere':'\uD83D\uDE23','cry':'\uD83D\uDE22',
    'joy':'\uD83D\uDE02','sob':'\uD83D\uDE2D','sleepy':'\uD83D\uDE2A','sweat':'\uD83D\uDE13',
    'cold_sweat':'\uD83D\uDE30','angry':'\uD83D\uDE20','rage':'\uD83D\uDE21',
    'triumph':'\uD83D\uDE24','mask':'\uD83D\uDE37','sunglasses':'\uD83D\uDE0E',
    'dizzy_face':'\uD83D\uDE35','imp':'\uD83D\uDC7F','neutral_face':'\uD83D\uDE10',
    'no_mouth':'\uD83D\uDE36','innocent':'\uD83D\uDE07','alien':'\uD83D\uDC7D',
    'yellow_heart':'\uD83D\uDC9B','blue_heart':'\uD83D\uDC99','purple_heart':'\uD83D\uDC9C',
    'heart':'\u2764\uFE0F','green_heart':'\uD83D\uDC9A','broken_heart':'\uD83D\uDC94',
    'heartbeat':'\uD83D\uDC93','heartpulse':'\uD83D\uDC97','sparkling_heart':'\uD83D\uDC96',
    'star':'\u2B50','star2':'\uD83C\uDF1F','sparkles':'\u2728','sunny':'\u2600\uFE0F',
    'cloud':'\u2601\uFE0F','zap':'\u26A1','fire':'\uD83D\uDD25','snowflake':'\u2744\uFE0F',
    'rainbow':'\uD83C\uDF08','ocean':'\uD83C\uDF0A','earth_americas':'\uD83C\uDF0E',
    'moon':'\uD83C\uDF19','sun_with_face':'\uD83C\uDF1E',
    'thumbsup':'\uD83D\uDC4D','thumbsdown':'\uD83D\uDC4E','ok_hand':'\uD83D\uDC4C',
    'punch':'\uD83D\uDC4A','fist':'\u270A','v':'\u270C\uFE0F','wave':'\uD83D\uDC4B',
    'hand':'\u270B','open_hands':'\uD83D\uDC50','point_up':'\u261D\uFE0F',
    'point_down':'\uD83D\uDC47','point_left':'\uD83D\uDC48','point_right':'\uD83D\uDC49',
    'raised_hands':'\uD83D\uDE4C','pray':'\uD83D\uDE4F','clap':'\uD83D\uDC4F',
    'muscle':'\uD83D\uDCAA','metal':'\uD83E\uDD18','fu':'\uD83D\uDD95',
    'walking':'\uD83D\uDEB6','runner':'\uD83C\uDFC3','dancer':'\uD83D\uDC83',
    'couple':'\uD83D\uDC6B','family':'\uD83D\uDC6A','boy':'\uD83D\uDC66',
    'girl':'\uD83D\uDC67','man':'\uD83D\uDC68','woman':'\uD83D\uDC69',
    'cop':'\uD83D\uDC6E','angel':'\uD83D\uDC7C',
    'dog':'\uD83D\uDC36','cat':'\uD83D\uDC31','mouse':'\uD83D\uDC2D','hamster':'\uD83D\uDC39',
    'rabbit':'\uD83D\uDC30','bear':'\uD83D\uDC3B','panda_face':'\uD83D\uDC3C',
    'pig':'\uD83D\uDC37','frog':'\uD83D\uDC38','monkey_face':'\uD83D\uDC35',
    'chicken':'\uD83D\uDC14','penguin':'\uD83D\uDC27','bird':'\uD83D\uDC26',
    'fish':'\uD83D\uDC1F','whale':'\uD83D\uDC33','bug':'\uD83D\uDC1B',
    'snake':'\uD83D\uDC0D','turtle':'\uD83D\uDC22','bee':'\uD83D\uDC1D',
    'cherry_blossom':'\uD83C\uDF38','rose':'\uD83C\uDF39','sunflower':'\uD83C\uDF3B',
    'four_leaf_clover':'\uD83C\uDF40','seedling':'\uD83C\uDF31','evergreen_tree':'\uD83C\uDF32',
    'palm_tree':'\uD83C\uDF34','cactus':'\uD83C\uDF35',
    'apple':'\uD83C\uDF4E','green_apple':'\uD83C\uDF4F','banana':'\uD83C\uDF4C',
    'grapes':'\uD83C\uDF47','watermelon':'\uD83C\uDF49','strawberry':'\uD83C\uDF53',
    'lemon':'\uD83C\uDF4B','peach':'\uD83C\uDF51','pizza':'\uD83C\uDF55',
    'hamburger':'\uD83C\uDF54','fries':'\uD83C\uDF5F','egg':'\uD83C\uDF73',
    'coffee':'\u2615','tea':'\uD83C\uDF75','beer':'\uD83C\uDF7A','wine_glass':'\uD83C\uDF77',
    'tada':'\uD83C\uDF89','balloon':'\uD83C\uDF88','gift':'\uD83C\uDF81',
    'trophy':'\uD83C\uDFC6','medal_sports':'\uD83C\uDFC5',
    'rocket':'\uD83D\uDE80','airplane':'\u2708\uFE0F','car':'\uD83D\uDE97',
    'bike':'\uD83D\uDEB2','ship':'\uD83D\uDEA2','train':'\uD83D\uDE82',
    'house':'\uD83C\uDFE0','school':'\uD83C\uDFEB','office':'\uD83C\uDFE2',
    'hospital':'\uD83C\uDFE5','church':'\u26EA','tent':'\u26FA',
    'watch':'\u231A','phone':'\u260E\uFE0F','computer':'\uD83D\uDCBB','bulb':'\uD83D\uDCA1',
    'battery':'\uD83D\uDD0B','key':'\uD83D\uDD11','lock':'\uD83D\uDD12',
    'unlock':'\uD83D\uDD13','bell':'\uD83D\uDD14','bookmark':'\uD83D\uDD16',
    'link':'\uD83D\uDD17','wrench':'\uD83D\uDD27','hammer':'\uD83D\uDD28',
    'scissors':'\u2702\uFE0F','pushpin':'\uD83D\uDCCC','paperclip':'\uD83D\uDCCE',
    'pencil2':'\u270F\uFE0F','memo':'\uD83D\uDCDD','book':'\uD83D\uDCD6',
    'books':'\uD83D\uDCDA','newspaper':'\uD83D\uDCF0','calendar':'\uD83D\uDCC5',
    'chart_with_upwards_trend':'\uD83D\uDCC8','chart_with_downwards_trend':'\uD83D\uDCC9',
    'email':'\u2709\uFE0F','inbox_tray':'\uD83D\uDCE5','outbox_tray':'\uD83D\uDCE4',
    'package':'\uD83D\uDCE6','mailbox':'\uD83D\uDCEB',
    'warning':'\u26A0\uFE0F','x':'\u274C','o':'\u2B55','white_check_mark':'\u2705',
    'heavy_check_mark':'\u2714\uFE0F','heavy_multiplication_x':'\u2716\uFE0F',
    'bangbang':'\u203C\uFE0F','question':'\u2753','exclamation':'\u2757',
    'grey_question':'\u2754','grey_exclamation':'\u2755',
    'recycle':'\u267B\uFE0F','beginner':'\uD83D\uDD30','trident':'\uD83D\uDD31',
    'checkered_flag':'\uD83C\uDFC1','triangular_flag_on_post':'\uD83D\uDEA9',
    'arrow_up':'\u2B06\uFE0F','arrow_down':'\u2B07\uFE0F','arrow_left':'\u2B05\uFE0F',
    'arrow_right':'\u27A1\uFE0F','arrow_upper_left':'\u2196\uFE0F','arrow_upper_right':'\u2197\uFE0F',
    'arrow_lower_left':'\u2199\uFE0F','arrow_lower_right':'\u2198\uFE0F',
    'information_source':'\u2139\uFE0F','abc':'\uD83D\uDD24',
    'thinking':'\uD83E\uDD14','eyes':'\uD83D\uDC40','skull':'\uD83D\uDC80',
    'ghost':'\uD83D\uDC7B','see_no_evil':'\uD83D\uDE48','hear_no_evil':'\uD83D\uDE49',
    'speak_no_evil':'\uD83D\uDE4A','sweat_smile':'\uD83D\uDE05','rofl':'\uD83E\uDD23',
    'slightly_smiling_face':'\uD83D\uDE42','upside_down_face':'\uD83D\uDE43',
    'nerd_face':'\uD83E\uDD13','party_popper':'\uD83C\uDF89',
    'raised_eyebrow':'\uD83E\uDD28','shrug':'\uD83E\uDD37','facepalm':'\uD83E\uDD26',
    'wave_dash':'\u3030\uFE0F','copyright':'\u00A9\uFE0F','registered':'\u00AE\uFE0F',
    'tm':'\u2122\uFE0F','infinity':'\u267E\uFE0F',
    'art':'\uD83C\uDFA8','musical_note':'\uD83C\uDFB5','microphone':'\uD83C\uDFA4',
    'headphones':'\uD83C\uDFA7','guitar':'\uD83C\uDFB8','trumpet':'\uD83C\uDFBA',
    'violin':'\uD83C\uDFBB','game_die':'\uD83C\uDFB2',
    'soccer':'\u26BD','basketball':'\uD83C\uDFC0','football':'\uD83C\uDFC8',
    'baseball':'\u26BE','tennis':'\uD83C\uDFBE','golf':'\u26F3',
    'tada_party':'\uD83C\uDF89','confetti_ball':'\uD83C\uDF8A',
    'gem':'\uD83D\uDC8E','ring':'\uD83D\uDC8D','crown':'\uD83D\uDC51',
    'moneybag':'\uD83D\uDCB0','dollar':'\uD83D\uDCB5','credit_card':'\uD83D\uDCB3',
    'chart':'\uD83D\uDCB9','bomb':'\uD83D\uDCA3','boom':'\uD83D\uDCA5',
    'zzz':'\uD83D\uDCA4','dash':'\uD83D\uDCA8','sweat_drops':'\uD83D\uDCA6',
    'notes':'\uD83C\uDFB6','speech_balloon':'\uD83D\uDCAC','thought_balloon':'\uD83D\uDCAD',
    'no_entry':'\u26D4','no_entry_sign':'\uD83D\uDEAB','underage':'\uD83D\uDD1E',
    'anger':'\uD83D\uDCA2','skull_and_crossbones':'\u2620\uFE0F'
  };
  var re = /:([a-z0-9_+-]+):/g;
  window.__applyEmoji = function(container) {
    var body = container || document.querySelector('.markdown-body') || document.body;
    var walker = document.createTreeWalker(body, NodeFilter.SHOW_TEXT, {
      acceptNode: function(node) {
        var p = node.parentNode;
        while (p && p !== body) {
          var tag = p.tagName;
          if (tag === 'PRE' || tag === 'CODE' || tag === 'SCRIPT' || tag === 'STYLE') return NodeFilter.FILTER_REJECT;
          p = p.parentNode;
        }
        return NodeFilter.FILTER_ACCEPT;
      }
    });
    var nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    nodes.forEach(function(node) {
      var text = node.textContent;
      if (!re.test(text)) return;
      re.lastIndex = 0;
      var newText = text.replace(re, function(match, code) {
        return map[code] || match;
      });
      if (newText !== text) node.textContent = newText;
    });
  };
  __applyEmoji();
})();
