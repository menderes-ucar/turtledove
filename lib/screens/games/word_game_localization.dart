import 'package:flutter/widgets.dart';

class WordGameStrings {
  final String code;
  const WordGameStrings(this.code);
  static WordGameStrings of(BuildContext context) {
    final c = Localizations.localeOf(context).languageCode;
    return WordGameStrings({'tr','en','de','es','fr'}.contains(c) ? c : 'en');
  }
  String _t(Map<String,String> v) => v[code] ?? v['en']!;
  String get score => _t({'tr':'Puan','en':'Score','de':'Punkte','es':'Puntuación','fr':'Score'});
  String get mistakes => _t({'tr':'Hata','en':'Mistakes','de':'Fehler','es':'Errores','fr':'Erreurs'});
  String get gameOver => _t({'tr':'Oyun bitti!','en':'Game over!','de':'Spiel vorbei!','es':'¡Fin del juego!','fr':'Partie terminée !'});
  String get finalScore => _t({'tr':'Final puan','en':'Final score','de':'Endpunktzahl','es':'Puntuación final','fr':'Score final'});
  String get restart => _t({'tr':'Yeniden başla','en':'Restart','de':'Neustart','es':'Reiniciar','fr':'Recommencer'});
  String get lastWord => _t({'tr':'Son kelime:','en':'Last word:','de':'Letztes Wort:','es':'Última palabra:','fr':'Dernier mot :'});
  String get nextLetterHint => _t({'tr':'Şu harfle başlayan kelime yaz:','en':'Enter a word starting with:','de':'Gib ein Wort ein, das beginnt mit:','es':'Escribe una palabra que empiece por:','fr':'Saisissez un mot commençant par :'});
  String get startHint => _t({'tr':'Kelime yaz ve başla!','en':'Enter a word to start!','de':'Gib ein Wort ein, um zu starten!','es':'¡Escribe una palabra para empezar!','fr':'Écrivez un mot pour commencer !'});
  String get words => _t({'tr':'Kelimeler:','en':'Words:','de':'Wörter:','es':'Palabras:','fr':'Mots :'});
  String get enterWord => _t({'tr':'Kelime gir...','en':'Enter a word...','de':'Wort eingeben...','es':'Escribe una palabra...','fr':'Saisissez un mot...'});
  String get mustStartWith => _t({'tr':'Kelime şu harfle başlamalı:','en':'The word must start with:','de':'Das Wort muss beginnen mit:','es':'La palabra debe empezar por:','fr':'Le mot doit commencer par :'});
  String get alreadyUsed => _t({'tr':'Bu kelime daha önce yazıldı! ❌','en':'This word was already used! ❌','de':'Dieses Wort wurde bereits verwendet! ❌','es':'¡Esta palabra ya fue usada! ❌','fr':'Ce mot a déjà été utilisé ! ❌'});
  String get added => _t({'tr':'eklendi!','en':'added!','de':'hinzugefügt!','es':'¡añadida!','fr':'ajouté !'});
  String get title => '🔤 ${_t({'tr':'Kelime Oyunu','en':'Word Chain','de':'Wortkette','es':'Cadena de palabras','fr':'Chaîne de mots'})}';
  String get chooseLanguage => _t({'tr':'Dil seç','en':'Choose a language','de':'Sprache wählen','es':'Elige un idioma','fr':'Choisir une langue'});
  String get dictionaryInfo => _t({'tr':'Oyundaki bütün kelimeler seçtiğin dilin sözlüğünden doğrulanır. Oyun başladıktan sonra dil değiştirilemez.','en':'Every word is validated against the selected language dictionary. The language cannot be changed after the game starts.','de':'Jedes Wort wird anhand des Wörterbuchs der gewählten Sprache geprüft. Nach Spielbeginn kann die Sprache nicht geändert werden.','es':'Todas las palabras se validan con el diccionario del idioma elegido. El idioma no se puede cambiar después de empezar.','fr':'Chaque mot est vérifié dans le dictionnaire de la langue choisie. La langue ne peut plus être changée après le début.'});
  String get play => _t({'tr':'Oyuna geç','en':'Continue','de':'Weiter','es':'Continuar','fr':'Continuer'});
  String get sameGame => _t({'tr':'Partnerinle aynı oyuna katıl','en':'Join the same game as your partner','de':'Am selben Spiel wie dein Partner teilnehmen','es':'Únete a la misma partida que tu pareja','fr':'Rejoignez la même partie que votre partenaire'});
  String get language => _t({'tr':'Dil','en':'Language','de':'Sprache','es':'Idioma','fr':'Langue'});
  String get you => _t({'tr':'Sen','en':'You','de':'Du','es':'Tú','fr':'Vous'});
  String get partner => _t({'tr':'Partnerin','en':'Partner','de':'Partner','es':'Pareja','fr':'Partenaire'});
  String get ready => _t({'tr':'Hazır','en':'Ready','de':'Bereit','es':'Listo','fr':'Prêt'});
  String get waiting => _t({'tr':'Bekliyor','en':'Waiting','de':'Wartet','es':'Esperando','fr':'En attente'});
  String get bothReady => _t({'tr':'İkiniz de hazırsınız. Oyun başlatılıyor...','en':'You are both ready. Starting the game...','de':'Ihr seid beide bereit. Das Spiel startet...','es':'Ambos están listos. El juego comienza...','fr':'Vous êtes tous les deux prêts. La partie démarre...'});
  String get waitingPartner => _t({'tr':'Partnerinin hazır olması bekleniyor.','en':'Waiting for your partner to be ready.','de':'Warten, bis dein Partner bereit ist.','es':'Esperando a que tu pareja esté lista.','fr':'En attente de votre partenaire.'});
  String get pressReady => _t({'tr':'Hazır olduğunda butona bas.','en':'Press the button when you are ready.','de':'Drücke den Button, wenn du bereit bist.','es':'Pulsa el botón cuando estés listo.','fr':'Appuyez sur le bouton quand vous êtes prêt.'});
  String get notReady => _t({'tr':'Hazır değilim','en':'Not ready','de':'Nicht bereit','es':'No estoy listo','fr':'Pas prêt'});
  String get imReady => _t({'tr':'Hazırım','en':'I’m ready','de':'Ich bin bereit','es':'Estoy listo','fr':'Je suis prêt'});
  String get retry => _t({'tr':'Tekrar dene','en':'Try again','de':'Erneut versuchen','es':'Reintentar','fr':'Réessayer'});
  String get beforePairing => _t({'tr':'Bu oyunu oynamak için önce partnerinle eşleşmelisin.','en':'Pair with your partner before playing this game.','de':'Verbinde dich zuerst mit deinem Partner, um dieses Spiel zu spielen.','es':'Vincúlate con tu pareja antes de jugar.','fr':'Associez-vous d’abord pour jouer à ce jeu.'});
  String get round => _t({'tr':'Tur','en':'Round','de':'Runde','es':'Ronda','fr':'Tour'});
  String startsWith(String l) => _t({'tr':'$l ile başlayan kelime','en':'Word starting with $l','de':'Wort mit $l','es':'Palabra que empieza por $l','fr':'Mot commençant par $l'});
  String get submit => _t({'tr':'Kelimeyi gönder','en':'Submit word','de':'Wort senden','es':'Enviar palabra','fr':'Envoyer le mot'});
  String get surrender => _t({'tr':'Pes Et','en':'Surrender','de':'Aufgeben','es':'Rendirse','fr':'Abandonner'});
  String get myTurn => _t({'tr':'Sıra sende 🎯','en':'Your turn 🎯','de':'Du bist dran 🎯','es':'Tu turno 🎯','fr':'À vous 🎯'});
  String get partnerTurn => _t({'tr':'Partnerin oynuyor ⏳','en':'Your partner is playing ⏳','de':'Dein Partner ist dran ⏳','es':'Tu pareja está jugando ⏳','fr':'Votre partenaire joue ⏳'});
  String get typeWord => _t({'tr':'Bu harfle başlayan bir kelime yaz','en':'Type a word starting with this letter','de':'Schreibe ein Wort mit diesem Anfangsbuchstaben','es':'Escribe una palabra que empiece por esta letra','fr':'Écrivez un mot commençant par cette lettre'});
  String get history => _t({'tr':'Oyun geçmişi','en':'Game history','de':'Spielverlauf','es':'Historial','fr':'Historique'});
  String get surrenderQuestion => _t({'tr':'Pes et?','en':'Surrender?','de':'Aufgeben?','es':'¿Rendirse?','fr':'Abandonner ?'});
  String get surrenderInfo => _t({'tr':'Pes edersen oyunu kaybedersin ve partnerin kazanır.','en':'If you surrender, you lose the game and your partner wins.','de':'Wenn du aufgibst, verlierst du und dein Partner gewinnt.','es':'Si te rindes, pierdes y tu pareja gana.','fr':'Si vous abandonnez, vous perdez et votre partenaire gagne.'});
  String get cancel => _t({'tr':'Vazgeç','en':'Cancel','de':'Abbrechen','es':'Cancelar','fr':'Annuler'});
  String get completed => _t({'tr':'🔤 Oyun tamamlandı','en':'🔤 Game complete','de':'🔤 Spiel beendet','es':'🔤 Juego terminado','fr':'🔤 Partie terminée'});
  String get chainComplete => _t({'tr':'Kelime zinciri tamamlandı!','en':'Word chain complete!','de':'Wortkette abgeschlossen!','es':'¡Cadena de palabras completada!','fr':'Chaîne de mots terminée !'});
  String played(int n) => _t({'tr':'$n geçerli kelime oynandı.','en':'$n valid words played.','de':'$n gültige Wörter gespielt.','es':'Se jugaron $n palabras válidas.','fr':'$n mots valides joués.'});
  String get home => _t({'tr':'Ana sayfaya dön','en':'Back to home','de':'Zur Startseite','es':'Volver al inicio','fr':'Retour à l’accueil'});
  String get won => _t({'tr':'🏆 Kazandın!','en':'🏆 You won!','de':'🏆 Du hast gewonnen!','es':'🏆 ¡Ganaste!','fr':'🏆 Vous avez gagné !'});
  String get lost => _t({'tr':'😔 Kaybettin','en':'😔 You lost','de':'😔 Du hast verloren','es':'😔 Has perdido','fr':'😔 Vous avez perdu'});
  String reason(String? r) => switch (r) {
    'surrender' => _t({'tr':'Rakibin pes etti.','en':'Your opponent surrendered.','de':'Dein Gegner hat aufgegeben.','es':'Tu oponente se rindió.','fr':'Votre adversaire a abandonné.'}),
    'three_mistakes' => _t({'tr':'Bir oyuncu 3 hata yaptı.','en':'A player made 3 mistakes.','de':'Ein Spieler hat 3 Fehler gemacht.','es':'Un jugador cometió 3 errores.','fr':'Un joueur a fait 3 erreurs.'}),
    _ => _t({'tr':'Oyun sona erdi.','en':'The game has ended.','de':'Das Spiel ist beendet.','es':'El juego ha terminado.','fr':'La partie est terminée.'}),
  };
}
