import '../models/game_category_model.dart';

class GameTypeConfig {
  final String gameType;
  final String title;
  final String emoji;
  final String answerHint;
  final String waitingMessage;
  final String locale;

  const GameTypeConfig({
    required this.gameType,
    required this.title,
    required this.emoji,
    required this.answerHint,
    required this.waitingMessage,
    this.locale = 'en',
  });

  static GameTypeConfig forType(String gameType, {String locale = 'en'}) {
    final l = {'tr', 'en', 'de', 'es', 'fr'}.contains(locale) ? locale : 'en';
    switch (gameType) {
      case 'most_likely_to':
        return GameTypeConfig(
          gameType: gameType,
          locale: l,
          title: {'tr':'Most Likely To','en':'Most Likely To','de':'Wer würde eher?','es':'Quién es más probable','fr':'Qui est le plus susceptible'}[l]!,
          emoji: '🎯',
          answerHint: {'tr':'Cevabını seç','en':'Choose your answer','de':'Wähle deine Antwort','es':'Elige tu respuesta','fr':'Choisissez votre réponse'}[l]!,
          waitingMessage: {'tr':'Partnerin de cevap verene kadar sonuç gizli.','en':'Results stay hidden until your partner answers.','de':'Die Ergebnisse bleiben verborgen, bis dein Partner antwortet.','es':'Los resultados permanecen ocultos hasta que tu pareja responda.','fr':'Les résultats restent cachés jusqu’à ce que votre partenaire réponde.'}[l]!,
        );
      case 'trivia':
        return GameTypeConfig(
          gameType: gameType,
          locale: l,
          title: 'Trivia',
          emoji: '🧠',
          answerHint: {'tr':'Doğru olduğunu düşündüğün cevabı seç','en':'Choose the answer you think is correct','de':'Wähle die deiner Meinung nach richtige Antwort','es':'Elige la respuesta que crees correcta','fr':'Choisissez la réponse que vous pensez correcte'}[l]!,
          waitingMessage: {'tr':'Partnerin cevap verene kadar sonucu göremezsin.','en':'You cannot see the result until your partner answers.','de':'Du siehst das Ergebnis erst, wenn dein Partner antwortet.','es':'No puedes ver el resultado hasta que tu pareja responda.','fr':'Vous ne verrez pas le résultat avant la réponse de votre partenaire.'}[l]!,
        );
      case 'word_game':
        return GameTypeConfig(
          gameType: gameType,
          locale: l,
          title: {'tr':'Kelime Oyunu','en':'Word Chain','de':'Wortkette','es':'Cadena de palabras','fr':'Chaîne de mots'}[l]!,
          emoji: '🔤',
          answerHint: {'tr':'Cevabını yaz','en':'Enter your word','de':'Gib dein Wort ein','es':'Escribe tu palabra','fr':'Saisissez votre mot'}[l]!,
          waitingMessage: {'tr':'Partnerin cevap verene kadar sonuç gizli.','en':'Results stay hidden until your partner answers.','de':'Die Ergebnisse bleiben verborgen, bis dein Partner antwortet.','es':'Los resultados permanecen ocultos hasta que tu pareja responda.','fr':'Les résultats restent cachés jusqu’à ce que votre partenaire réponde.'}[l]!,
        );
      default:
        return GameTypeConfig(
          gameType: gameType,
          locale: l,
          title: {'tr':'Oyun','en':'Game','de':'Spiel','es':'Juego','fr':'Jeu'}[l]!,
          emoji: '🎮',
          answerHint: {'tr':'Cevabını seç veya yaz','en':'Choose or enter your answer','de':'Wähle oder gib deine Antwort ein','es':'Elige o escribe tu respuesta','fr':'Choisissez ou saisissez votre réponse'}[l]!,
          waitingMessage: {'tr':'Partnerin cevap verene kadar sonuç gizli.','en':'Results stay hidden until your partner answers.','de':'Die Ergebnisse bleiben verborgen, bis dein Partner antwortet.','es':'Los resultados bleiben verborgen, bis dein Partner antwortet.','fr':'Les résultats restent cachés jusqu’à ce que votre partenaire réponde.'}[l]!,
        );
    }
  }

  List<GameCategory> get categories {
    final data = <String, List<GameCategory>>{
      'most_likely_to': [
        _cat('relationship','❤️', {'tr':'İlişki','en':'Relationship','de':'Beziehung','es':'Relación','fr':'Relation'}, ['Partneri Tanıma','Knowing Your Partner','Partner kennenlernen','Conocer a tu pareja','Connaître son partenaire'], ['Günlük Hayat','Daily Life','Alltag','Vida diaria','Vie quotidienne']),
        _cat('funny','😂', {'tr':'Komik','en':'Funny','de':'Lustig','es':'Divertido','fr':'Amusant'}, ['Günlük Hayat','Daily Life','Alltag','Vida diaria','Vie quotidienne'], ['Absürt','Absurd','Absurd','Absurdas','Absurde']),
        _cat('lifestyle','✨', {'tr':'Yaşam Tarzı','en':'Lifestyle','de':'Lebensstil','es':'Estilo de vida','fr':'Style de vie'}, ['Ev','Home','Zuhause','Hogar','Maison'], ['Para','Money','Geld','Dinero','Argent']),
        _cat('travel','✈️', {'tr':'Seyahat','en':'Travel','de':'Reisen','es':'Viajes','fr':'Voyage'}, ['Tatil','Vacation','Urlaub','Vacaciones','Vacances'], ['Macera','Adventure','Abenteuer','Aventura','Aventure']),
        _cat('food','🍕', {'tr':'Yemek','en':'Food','de':'Essen','es':'Comida','fr':'Cuisine'}, ['Favoriler','Favorites','Favoriten','Favoritos','Favoris'], ['Restoran','Restaurants','Restaurants','Restaurantes','Restaurants']),
        _simple('career','💼', {'tr':'Kariyer & Para','en':'Career & Money','de':'Karriere & Geld','es':'Carrera y dinero','fr':'Carrière & argent'}),
        _cat('hard_choices','🔥', {'tr':'Zor Seçimler','en':'Hard Choices','de':'Schwierige Entscheidungen','es':'Decisiones difíciles','fr':'Choix difficiles'}, ['İkilemler','Dilemmas','Dilemmata','Dilemas','Dilemmes'], ['Cesur Sorular','Bold Questions','Mutige Fragen','Preguntas atrevidas','Questions audacieuses']),
      ],
      'trivia': [
        _simple('general','🌎', {'tr':'Genel Kültür','en':'General Knowledge','de':'Allgemeinwissen','es':'Cultura general','fr':'Culture générale'}),
        _simple('movies_series','🎬', {'tr':'Film & Dizi','en':'Movies & Series','de':'Filme & Serien','es':'Películas y series','fr':'Films & séries'}),
        _simple('music','🎵', {'tr':'Müzik','en':'Music','de':'Musik','es':'Música','fr':'Musique'}),
        _simple('travel','✈️', {'tr':'Dünya & Seyahat','en':'World & Travel','de':'Welt & Reisen','es':'Mundo y viajes','fr':'Monde & voyage'}),
        _simple('food','🍔', {'tr':'Yemek','en':'Food','de':'Essen','es':'Comida','fr':'Cuisine'}),
        _simple('science','🔬', {'tr':'Bilim','en':'Science','de':'Wissenschaft','es':'Ciencia','fr':'Science'}),
        _simple('history','🏛️', {'tr':'Tarih & Kültür','en':'History & Culture','de':'Geschichte & Kultur','es':'Historia y cultura','fr':'Histoire & culture'}),
      ],
      'name_city_animal': [
        _simple('classic','🎯', {'tr':'Klasik','en':'Classic','de':'Klassisch','es':'Clásico','fr':'Classique'}),
      ],
      'word_game': [
        _simple('general','🔤', {'tr':'Genel','en':'General','de':'Allgemein','es':'General','fr':'Général'}),
        _simple('relationship','❤️', {'tr':'İlişki','en':'Relationship','de':'Beziehung','es':'Relación','fr':'Relation'}),
        _simple('movies_series','🎬', {'tr':'Film & Dizi','en':'Movies & Series','de':'Filme & Serien','es':'Películas y series','fr':'Films & séries'}),
        _simple('food','🍕', {'tr':'Yemek','en':'Food','de':'Essen','es':'Comida','fr':'Cuisine'}),
        _simple('travel','✈️', {'tr':'Seyahat','en':'Travel','de':'Reisen','es':'Viajes','fr':'Voyage'}),
      ],
    };
    return data[gameType] ?? const [];
  }

  GameCategory _simple(String id, String emoji, Map<String,String> title) => GameCategory(id: id, title: title[locale] ?? title['en']!, emoji: emoji);
  GameCategory _cat(String id, String emoji, Map<String,String> title, List<String> sub1, List<String> sub2) => GameCategory(id: id, title: title[locale] ?? title['en']!, emoji: emoji, subcategories: [sub1[_index()], sub2[_index()]]);
  int _index() => const ['tr','en','de','es','fr'].indexOf(locale);
}
