import 'package:flutter/widgets.dart';

class PetStrings {
  final String code;
  const PetStrings(this.code);

  static PetStrings of(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode;
    return PetStrings({'tr', 'en', 'de', 'es', 'fr'}.contains(code) ? code : 'en');
  }

  String get title => _t({'tr':'Turtle Dove Evcil Hayvan','en':'Turtle Dove Pet','de':'Turtle Dove Haustier','es':'Mascota Turtle Dove','fr':'Animal Turtle Dove'});
  String get sharedPet => _t({'tr':'Ortak evcil hayvanınız','en':'Your shared pet','de':'Euer gemeinsames Haustier','es':'Vuestra mascota compartida','fr':'Votre animal partagé'});
  String get sharedPetInfo => _t({'tr':'Tek bir evcil hayvanı birlikte büyütün. Her bakım, oyun ve sevgi iki taraf için de aynı ortak yaşamı günceller.','en':'Raise one pet together. Every care action, game and cuddle updates the same shared life for both partners.','de':'Zieht gemeinsam ein Haustier groß. Jede Pflege und jedes Spiel aktualisiert dasselbe gemeinsame Leben.','es':'Críen una mascota juntos. Cada cuidado y juego actualiza la misma vida compartida.','fr':'Élevez un animal ensemble. Chaque soin et chaque jeu met à jour la même vie partagée.'});
  String get petName => _t({'tr':'Evcil hayvan adı','en':'Pet name','de':'Name des Haustiers','es':'Nombre de mascota','fr':'Nom de l’animal'});
  String get create => _t({'tr':'Evcil hayvanımızı oluştur','en':'Create our pet','de':'Unser Haustier erstellen','es':'Crear nuestra mascota','fr':'Créer notre animal'});
  String get carePlay => _t({'tr':'Bakım ve yaşam','en':'Care & life','de':'Pflege & Leben','es':'Cuidado y vida','fr':'Soins & vie'});
  String get hunger => _t({'tr':'Açlık','en':'Hunger','de':'Hunger','es':'Hambre','fr':'Faim'});
  String get hygiene => _t({'tr':'Temizlik','en':'Hygiene','de':'Hygiene','es':'Higiene','fr':'Hygiène'});
  String get energy => _t({'tr':'Enerji','en':'Energy','de':'Energie','es':'Energía','fr':'Énergie'});
  String get fun => _t({'tr':'Eğlence','en':'Fun','de':'Spaß','es':'Diversión','fr':'Amusement'});
  String get health => _t({'tr':'Sağlık','en':'Health','de':'Gesundheit','es':'Salud','fr':'Santé'});
  String get toilet => _t({'tr':'Tuvalet','en':'Toilet','de':'Toilette','es':'Baño','fr':'Toilettes'});
  String get affectionLabel => _t({'tr':'Sevgi','en':'Affection','de':'Zuneigung','es':'Cariño','fr':'Affection'});
  String get sharedBond => _t({'tr':'Ortak bağınız','en':'Your shared bond','de':'Eure gemeinsame Bindung','es':'Vuestro vínculo','fr':'Votre lien partagé'});
  String get feed => _t({'tr':'Besle','en':'Feed','de':'Füttern','es':'Dar de comer','fr':'Nourrir'});
  String get bath => _t({'tr':'Banyo','en':'Bath','de':'Baden','es':'Bañar','fr':'Bain'});
  String get clean => _t({'tr':'Temizle','en':'Clean','de':'Reinigen','es':'Limpiar','fr':'Nettoyer'});
  String get nails => _t({'tr':'Tırnak','en':'Nails','de':'Krallen','es':'Uñas','fr':'Griffes'});
  String get toiletAction => _t({'tr':'Tuvalet','en':'Toilet','de':'Toilette','es':'Baño','fr':'Toilettes'});
  String get play => _t({'tr':'Oyna','en':'Play','de':'Spielen','es':'Jugar','fr':'Jouer'});
  String get sleep => _t({'tr':'Uyut','en':'Sleep','de':'Schlafen','es':'Dormir','fr':'Dormir'});
  String get love => _t({'tr':'Sevgi','en':'Cuddle','de':'Kuscheln','es':'Mimos','fr':'Câliner'});
  String get level => _t({'tr':'Seviye','en':'Level','de':'Level','es':'Nivel','fr':'Niveau'});
  String get maxLevel => _t({'tr':'1000. SEVİYE — USTA PET','en':'LEVEL 1000 — PET MASTER','de':'LEVEL 1000 — PET-MEISTER','es':'NIVEL 1000 — MAESTRO PET','fr':'NIVEAU 1000 — MAÎTRE PET'});
  String get coinsLabel => _t({'tr':'Coin','en':'Coins','de':'Münzen','es':'Monedas','fr':'Pièces'});
  String get roomHome => _t({'tr':'Oyun odası','en':'Play room','de':'Spielzimmer','es':'Sala de juegos','fr':'Salle de jeu'});
  String get roomBath => _t({'tr':'Banyo & bakım','en':'Bath & grooming','de':'Bad & Pflege','es':'Baño y cuidado','fr':'Bain & toilettage'});
  String get roomSleep => _t({'tr':'Uyku odası','en':'Sleep room','de':'Schlafzimmer','es':'Dormitorio','fr':'Chambre'});
  String get roomKitchen => _t({'tr':'Mama köşesi','en':'Feeding corner','de':'Futterecke','es':'Rincón de comida','fr':'Coin repas'});
  String get baby => _t({'tr':'Bebek','en':'Baby','de':'Baby','es':'Bebé','fr':'Bébé'});
  String get child => _t({'tr':'Çocuk','en':'Child','de':'Kind','es':'Niño','fr':'Enfant'});
  String get young => _t({'tr':'Genç','en':'Young','de':'Jung','es':'Joven','fr':'Jeune'});
  String get teen => _t({'tr':'Ergen','en':'Teen','de':'Teenager','es':'Adolescente','fr':'Ado'});
  String get adult => _t({'tr':'Yetişkin','en':'Adult','de':'Erwachsen','es':'Adulto','fr':'Adulte'});
  String get mature => _t({'tr':'Olgun','en':'Mature','de':'Ausgewachsen','es':'Maduro','fr':'Mature'});
  String get senior => _t({'tr':'Usta','en':'Senior','de':'Senior','es':'Senior','fr':'Senior'});


  String get roomPlayShort => _t({'tr':'Oyun','en':'Play','de':'Spiel','es':'Juego','fr':'Jeu'});
  String get roomCareShort => _t({'tr':'Bakım','en':'Care','de':'Pflege','es':'Cuidado','fr':'Soin'});
  String get roomSleepShort => _t({'tr':'Uyku','en':'Sleep','de':'Schlaf','es':'Sueño','fr':'Sommeil'});
  String get roomFoodShort => _t({'tr':'Mama','en':'Food','de':'Futter','es':'Comida','fr':'Nourriture'});
  String get loading3d => _t({'tr':'3D yükleniyor','en':'Loading 3D','de':'3D wird geladen','es':'Cargando 3D','fr':'Chargement 3D'});
  String get petAssetMissing => _t({'tr':'3D evcil hayvan modeli bulunamadı','en':'3D pet asset is missing','de':'3D-Haustiermodell fehlt','es':'Falta el modelo 3D de la mascota','fr':'Modèle 3D de l’animal manquant'});

  String get speciesLabel => _t({'tr':'Hayvan türü','en':'Pet species','de':'Tierart','es':'Tipo de mascota','fr':'Espèce'});
  String get breedLabel => _t({'tr':'Cins / varyete','en':'Breed / variety','de':'Rasse / Variante','es':'Raza / variedad','fr':'Race / variété'});
  String get roomHomeSubtitle => _t({'tr':'Ona özel oyun ve bağlanma alanı','en':'A space for play and bonding','de':'Ein Ort zum Spielen und Kuscheln','es':'Un espacio para jugar y conectar','fr':'Un espace pour jouer et créer du lien'});
  String get roomBathSubtitle => _t({'tr':'Tüy, pati ve bakım istasyonu','en':'Fur, paws and grooming station','de':'Station für Fell, Pfoten und Pflege','es':'Estación de higiene y cuidado','fr':'Station de toilettage et de soins'});
  String get roomSleepSubtitle => _t({'tr':'Sessiz uyku ve dinlenme alanı','en':'A quiet place to sleep and rest','de':'Ruhiger Ort zum Schlafen und Ausruhen','es':'Un lugar tranquilo para dormir y descansar','fr':'Un endroit calme pour dormir et se reposer'});
  String get roomKitchenSubtitle => _t({'tr':'Mama ve ödül istasyonu','en':'Food and treat station','de':'Futter- und Snackstation','es':'Estación de comida y premios','fr':'Station de repas et friandises'});
  String speciesName(String value) => switch (code) {
    'tr' => {'cat':'Kedi','dog':'Köpek','rabbit':'Tavşan','bird':'Kuş','hamster':'Hamster','fox':'Tilki','snake':'Yılan'}[value] ?? value,
    'de' => {'cat':'Katze','dog':'Hund','rabbit':'Kaninchen','bird':'Vogel','hamster':'Hamster','fox':'Fuchs','snake':'Schlange'}[value] ?? value,
    'es' => {'cat':'Gato','dog':'Perro','rabbit':'Conejo','bird':'Ave','hamster':'Hámster','fox':'Zorro','snake':'Serpiente'}[value] ?? value,
    'fr' => {'cat':'Chat','dog':'Chien','rabbit':'Lapin','bird':'Oiseau','hamster':'Hamster','fox':'Renard','snake':'Serpent'}[value] ?? value,
    _ => {'cat':'Cat','dog':'Dog','rabbit':'Rabbit','bird':'Bird','hamster':'Hamster','fox':'Fox','snake':'Snake'}[value] ?? value,
  };
  List<String> get phrases => {
    'tr': ['Beni sevdin mi? 🥹','Bugün birlikte ne yapıyoruz?','Karnım biraz acıktı! 🍖','Benimle oynar mısın? 🎾','İkinizi de çok seviyorum! ❤️'],
    'en': ['Did you miss me? 🥹','What are we doing today?','I am getting hungry! 🍖','Will you play with me? 🎾','I love you both! ❤️'],
    'de': ['Hast du mich vermisst? 🥹','Was machen wir heute?','Ich bekomme Hunger! 🍖','Spielst du mit mir? 🎾','Ich liebe euch! ❤️'],
    'es': ['¿Me extrañaste? 🥹','¿Qué hacemos hoy?','¡Tengo un poco de hambre! 🍖','¿Jugamos? 🎾','¡Os quiero! ❤️'],
    'fr': ['Je vous ai manqué ? 🥹','Qu’est-ce qu’on fait aujourd’hui ?','J’ai un peu faim ! 🍖','On joue ? 🎾','Je vous aime ! ❤️'],
  }[code] ?? const ['Hi! 🐾'];

  String affection(int n) => '${affectionLabel} $n%';
  String coins(int n) => '$n $coinsLabel';
  String xp(int n) => '$n/1000 XP';
  String actionError(Object error) {
    final text = error.toString();
    final match = RegExp(r'ACTION_COOLDOWN:[^:]+:(\d+)').firstMatch(text);
    if (match != null) return cooldown(int.tryParse(match.group(1)!) ?? 5);
    if (text.contains('PAIR_REQUIRED')) return _t({'tr':'Önce partnerinle eşleşmelisin.','en':'Pair with your partner first.','de':'Bitte zuerst mit deinem Partner verbinden.','es':'Primero debes vincularte con tu pareja.','fr':'Associez-vous d’abord à votre partenaire.'});
    return _t({'tr':'İşlem şu anda tamamlanamadı. Lütfen tekrar deneyin.','en':'That action could not be completed. Please try again.','de':'Die Aktion konnte nicht abgeschlossen werden. Bitte erneut versuchen.','es':'No se pudo completar la acción. Inténtalo de nuevo.','fr':'Cette action n’a pas pu être effectuée. Réessayez.'});
  }
  String cooldown(int minutes) => minutes >= 60
      ? _t({'tr':'Biraz bekleyin • $minutes dk sonra tekrar kullanılabilir','en':'Take a break • available again in $minutes min','de':'Kurze Pause • wieder in $minutes Min. verfügbar','es':'Haz una pausa • disponible en $minutes min','fr':'Faites une pause • disponible dans $minutes min'})
      : _t({'tr':'Biraz bekleyin • $minutes dakika sonra tekrar','en':'Take a break • available again in $minutes minutes','de':'Kurze Pause • wieder in $minutes Minuten','es':'Haz una pausa • disponible en $minutes minutos','fr':'Faites une pause • disponible dans $minutes minutes'});
  String _t(Map<String, String> values) => values[code] ?? values['en']!;
}
