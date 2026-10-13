import 'package:flutter/widgets.dart';

class NameCityAnimalStrings {
  final String code;
  const NameCityAnimalStrings(this.code);

  static NameCityAnimalStrings of(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode;
    return NameCityAnimalStrings({'tr', 'en', 'de', 'es', 'fr'}.contains(code) ? code : 'en');
  }

  String _t(Map<String, String> values) => values[code] ?? values['en']!;

  String get error => _t({
    'tr': 'Bir hata oluştu',
    'en': 'Something went wrong',
    'de': 'Ein Fehler ist aufgetreten',
    'es': 'Ha ocurrido un error',
    'fr': 'Une erreur est survenue',
  });

  String get retry => _t({
    'tr': 'Tekrar dene',
    'en': 'Retry',
    'de': 'Erneut versuchen',
    'es': 'Reintentar',
    'fr': 'Réessayer',
  });

  String get title => _t({'tr':'İsim Şehir Hayvan','en':'Name City Animal','de':'Name, Stadt, Tier','es':'Nombre, ciudad y animal','fr':'Prénom, ville, animal'});
  String get chooseLanguage => _t({'tr':'Oyun dilini seç','en':'Choose game language','de':'Spielsprache wählen','es':'Elige el idioma del juego','fr':'Choisir la langue du jeu'});
  String get languageInfo => _t({'tr':'İki oyuncu da aynı dilde oynar. Cevaplar o dilin sözlüğüne göre doğrulanır.','en':'Both players use the same language. Answers are validated against that language’s dictionary.','de':'Beide Spieler spielen in derselben Sprache. Antworten werden anhand des Wörterbuchs dieser Sprache geprüft.','es':'Ambos jugadores usan el mismo idioma. Las respuestas se validan con el diccionario de ese idioma.','fr':'Les deux joueurs utilisent la même langue. Les réponses sont vérifiées avec le dictionnaire correspondant.'});
  String get ready => _t({'tr':'Hazırım','en':'Ready','de':'Bereit','es':'Listo','fr':'Prêt'});
  String get notReady => _t({'tr':'Hazır değilim','en':'Not ready','de':'Nicht bereit','es':'No estoy listo','fr':'Pas prêt'});
  String get waiting => _t({'tr':'Partnerin bekleniyor','en':'Waiting for your partner','de':'Auf den Partner warten','es':'Esperando a tu pareja','fr':'En attente du partenaire'});
  String get bothReady => _t({'tr':'İkiniz de hazırsınız. Oyun başlıyor…','en':'You are both ready. The game is starting…','de':'Ihr seid beide bereit. Das Spiel startet…','es':'Ambos están listos. El juego comienza…','fr':'Vous êtes tous les deux prêts. La partie commence…'});
  String get round => _t({'tr':'Tur','en':'Round','de':'Runde','es':'Ronda','fr':'Manche'});
  String get letter => _t({'tr':'Harf','en':'Letter','de':'Buchstabe','es':'Letra','fr':'Lettre'});
  String get name => _t({'tr':'İsim','en':'Name','de':'Name','es':'Nombre','fr':'Prénom'});
  String get city => _t({'tr':'Şehir','en':'City','de':'Stadt','es':'Ciudad','fr':'Ville'});
  String get animal => _t({'tr':'Hayvan','en':'Animal','de':'Tier','es':'Animal','fr':'Animal'});
  String get enterName => _t({'tr':'İsim yaz','en':'Enter a name','de':'Namen eingeben','es':'Escribe un nombre','fr':'Saisissez un prénom'});
  String get enterCity => _t({'tr':'Şehir yaz','en':'Enter a city','de':'Stadt eingeben','es':'Escribe una ciudad','fr':'Saisissez une ville'});

  String get plant => _t({'tr':'Bitki','en':'Plant','de':'Pflanze','es':'Planta','fr':'Plante'});
  String get thing => _t({'tr':'Eşya','en':'Thing','de':'Gegenstand','es':'Objeto','fr':'Objet'});
  String get country => _t({'tr':'Ülke','en':'Country','de':'Land','es':'País','fr':'Pays'});
  String get enterPlant => _t({'tr':'Bitki yaz','en':'Enter a plant','de':'Pflanze eingeben','es':'Escribe una planta','fr':'Saisissez une plante'});
  String get enterThing => _t({'tr':'Eşya yaz','en':'Enter a thing','de':'Gegenstand eingeben','es':'Escribe un objeto','fr':'Saisissez un objet'});
  String get enterCountry => _t({'tr':'Ülke yaz','en':'Enter a country','de':'Land eingeben','es':'Escribe un país','fr':'Saisissez un pays'});

  String get enterAnimal => _t({'tr':'Hayvan yaz','en':'Enter an animal','de':'Tier eingeben','es':'Escribe un animal','fr':'Saisissez un animal'});
  String get submit => _t({'tr':'Cevapları gönder','en':'Submit answers','de':'Antworten senden','es':'Enviar respuestas','fr':'Envoyer les réponses'});
  String get waitingOther => _t({'tr':'Cevapların kaydedildi. Partnerinin cevapları bekleniyor.','en':'Your answers are saved. Waiting for your partner.','de':'Deine Antworten wurden gespeichert. Wir warten auf deinen Partner.','es':'Tus respuestas se han guardado. Esperando a tu pareja.','fr':'Tes réponses sont enregistrées. En attente du partenaire.'});
  String get waitingReview => _t({'tr':'İkinizin cevapları alındı. Süre bitince cevaplar kontrol edilecek.','en':'Both answers are saved. Review starts when the timer ends.','de':'Beide Antworten sind gespeichert. Die Prüfung beginnt nach Ablauf der Zeit.','es':'Ambas respuestas están guardadas. La revisión comienza cuando termine el tiempo.','fr':'Les deux réponses sont enregistrées. La vérification commence à la fin du temps.'});
  String get reviewTitle => _t({'tr':'Cevapları kontrol et','en':'Review the answers','de':'Antworten prüfen','es':'Revisar respuestas','fr':'Vérifier les réponses'});
  String get reviewInfo => _t({'tr':'Partnerinin her cevabını kategoriye uygun mu diye işaretle. Sistem doğrulaması da gösterilir.','en':'Mark each partner answer as accepted or rejected. The server validation is shown too.','de':'Bewerte jede Antwort des Partners als akzeptiert oder abgelehnt. Die Serverprüfung wird ebenfalls angezeigt.','es':'Marca cada respuesta de tu pareja como aceptada o rechazada. También se muestra la validación del servidor.','fr':'Marquez chaque réponse de votre partenaire comme acceptée ou refusée. La validation du serveur est également affichée.'});
  String get confirmReview => _t({'tr':'Kontrolü onayla','en':'Confirm review','de':'Prüfung bestätigen','es':'Confirmar revisión','fr':'Confirmer la vérification'});
  String get reviewComplete => _t({'tr':'İkiniz de kontrolü tamamladınız. Sonraki tur hazırlanıyor.','en':'Both reviews are complete. The next round is starting.','de':'Beide Prüfungen sind abgeschlossen. Die nächste Runde startet.','es':'Ambas revisiones están completas. Comienza la siguiente ronda.','fr':'Les deux vérifications sont terminées. La prochaine manche commence.'});
  String get waitingPartnerReview => _t({'tr':'Kontrolün kaydedildi. Partnerinin kontrolü bekleniyor.','en':'Your review is saved. Waiting for your partner’s review.','de':'Deine Prüfung ist gespeichert. Wir warten auf die Prüfung deines Partners.','es':'Tu revisión está guardada. Esperando la revisión de tu pareja.','fr':'Votre vérification est enregistrée. En attente de celle de votre partenaire.'});
  String get systemValidationInfo => _t({'tr':'Puanlama: sistemin geçerli bulduğu ve partnerin onayladığı cevaplar puan alır. Aynı cevap iki oyuncuya da 1 puan verir.','en':'Scoring: answers must pass server validation and partner review. The same answer gives 1 point to each player.','de':'Wertung: Antworten müssen die Serverprüfung und die Partnerprüfung bestehen. Gleiche Antworten geben beiden 1 Punkt.','es':'Puntuación: las respuestas deben superar la validación del servidor y la revisión de la pareja. Una respuesta igual da 1 punto a cada jugador.','fr':'Score : les réponses doivent passer la validation du serveur et l’avis du partenaire. Une réponse identique donne 1 point à chacun.'});
  String get timeUp => _t({'tr':'Süre doldu','en':'Time is up','de':'Zeit abgelaufen','es':'Se acabó el tiempo','fr':'Temps écoulé'});
  String get score => _t({'tr':'Puan','en':'Score','de':'Punkte','es':'Puntuación','fr':'Score'});
  String get you => _t({'tr':'Sen','en':'You','de':'Du','es':'Tú','fr':'Vous'});
  String get partner => _t({'tr':'Partnerin','en':'Partner','de':'Partner','es':'Pareja','fr':'Partenaire'});
  String get valid => _t({'tr':'Geçerli','en':'Valid','de':'Gültig','es':'Válida','fr':'Valide'});
  String get invalid => _t({'tr':'Geçersiz','en':'Invalid','de':'Ungültig','es':'No válida','fr':'Invalide'});
  String get noAnswer => _t({'tr':'Boş','en':'Blank','de':'Leer','es':'Vacío','fr':'Vide'});
  String get results => _t({'tr':'Tur sonuçları','en':'Round results','de':'Rundenergebnis','es':'Resultado de la ronda','fr':'Résultats de la manche'});
  String get completed => _t({'tr':'Oyun bitti','en':'Game complete','de':'Spiel beendet','es':'Juego terminado','fr':'Partie terminée'});
  String get winner => _t({'tr':'Kazanan','en':'Winner','de':'Gewinner','es':'Ganador','fr':'Gagnant'});
  String get tie => _t({'tr':'Berabere','en':'Tie','de':'Unentschieden','es':'Empate','fr':'Égalité'});
  String get surrender => _t({'tr':'Oyundan çık','en':'Surrender','de':'Aufgeben','es':'Abandonieren','fr':'Abandonner'});
  String get surrenderQuestion => _t({'tr':'Oyundan çıkmak istiyor musun?','en':'Do you want to surrender?','de':'Möchtest du aufgeben?','es':'¿Quieres abandonar?','fr':'Voulez-vous abandonner ?'});
  String get cancel => _t({'tr':'İptal','en':'Cancel','de':'Abbrechen','es':'Cancelar','fr':'Annuler'});
  String get home => _t({'tr':'Ana sayfa','en':'Home','de':'Startseite','es':'Inicio','fr':'Accueil'});
  String remaining(int seconds) => _t({'tr':'$seconds sn','en':'$seconds s','de':'$seconds Sek.','es':'$seconds s','fr':'$seconds s'});
  String points(int n) => '+$n';
}
