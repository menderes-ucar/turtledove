import 'package:flutter/widgets.dart';

/// App-level strings for the shared navigation and relationship hub.
/// The app follows the device locale and falls back to English.
class AppStrings {
  final String code;
  const AppStrings(this.code);

  static AppStrings of(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode;
    return AppStrings({'tr', 'en', 'de', 'es', 'fr'}.contains(code) ? code : 'en');
  }

  String _t(Map<String, String> values) => values[code] ?? values['en']!;

  String t(String key) {
    const values = <String, Map<String, String>>{

      'conversation_finder': {'tr':'Konu Bulma','en':'Conversation Finder','de':'Gesprächsthemen','es':'Temas de conversación','fr':'Sujets de conversation'},
      'conversation_topics': {'tr':'Sohbet Konuları','en':'Conversation Topics','de':'Gesprächsthemen','es':'Temas de conversación','fr':'Sujets de conversation'},
      'jokes': {'tr':'Şakalar','en':'Jokes','de':'Witze','es':'Chistes','fr':'Blagues'},
      'mark_as_asked': {'tr':'Soruldu olarak işaretle','en':'Mark as asked','de':'Als gefragt markieren','es':'Marcar como preguntado','fr':'Marquer comme demandé'},
      'asked': {'tr':'Soruldu','en':'Asked','de':'Gefragt','es':'Pregunté','fr':'Demandé'},
      'answer_optional': {'tr':'Cevap ekle (opsiyonel)','en':'Add an answer (optional)','de':'Antwort hinzufügen (optional)','es':'Añadir una respuesta (opcional)','fr':'Ajouter une réponse (facultatif)'},
      'add_your_own_topic': {'tr':'Kendi konunu ekle','en':'Add your own topic','de':'Eigenes Thema hinzufügen','es':'Añade tu propio tema','fr':'Ajouter votre propre sujet'},
      'topic_question': {'tr':'Konu / soru','en':'Topic / question','de':'Thema / Frage','es':'Tema / pregunta','fr':'Sujet / question'},
      'answer': {'tr':'Cevap','en':'Answer','de':'Antwort','es':'Respuesta','fr':'Réponse'},
      'topic_added': {'tr':'Konu eklendi','en':'Topic added','de':'Thema hinzugefügt','es':'Tema añadido','fr':'Sujet ajouté'},
      'topic_save_failed': {'tr':'Konu kaydedilemedi','en':'Could not save topic','de':'Thema konnte nicht gespeichert werden','es':'No se pudo guardar el tema','fr':'Impossible d’enregistrer le sujet'},
      'topics_load_failed': {'tr':'Konular yüklenemedi','en':'Could not load topics','de':'Themen konnten nicht geladen werden','es':'No se pudieron cargar los temas','fr':'Impossible de charger les sujets'},
      'no_topics': {'tr':'Henüz konu yok','en':'No topics yet','de':'Noch keine Themen','es':'Aún no hay temas','fr':'Aucun sujet pour le moment'},
      'conversation_finder_subtitle': {'tr':'Birbirinizi daha iyi tanıyın, konuşacak yeni şeyler bulun.','en':'Get to know each other and find something new to talk about.','de':'Lernt euch besser kennen und findet neue Gesprächsthemen.','es':'Conózcanse mejor y encuentren nuevos temas de conversación.','fr':'Apprenez à mieux vous connaître et trouvez de nouveaux sujets.'},
      'love_letter_received_by': {'tr': '{sender} sana bir mektup gönderdi.', 'en': '{sender} sent you a letter.', 'de': '{sender} hat dir einen Brief geschickt.', 'es': '{sender} te envió una carta.', 'fr': '{sender} vous a envoyé une lettre.'},
      'bestie_area_start': {'tr':'Bestie alanını birlikte kullanmaya başlayın','en':'Start using Bestie together','de':'Startet gemeinsam mit Bestie','es':'Empiecen a usar Bestie juntos','fr':'Commencez à utiliser Bestie ensemble'},
      'delete_failed': {'tr':'Silinemedi','en':'Could not delete','de':'Löschen fehlgeschlagen','es':'No se pudo eliminar','fr':'Suppression impossible'},
      'interaction_hug': {'tr':'Sarılma','en':'Hug','de':'Umarmung','es':'Abrazo','fr':'Câlin'},
      'interaction_kiss': {'tr':'Öpücük','en':'Kiss','de':'Kuss','es':'Beso','fr':'Bisou'},
      'interaction_nudge': {'tr':'Dürtme','en':'Nudge','de':'Anstupsen','es':'Toque','fr':'Petit signe'},
      'interaction_miss_you': {'tr':'Seni özledim','en':'Miss you','de':'Ich vermisse dich','es':'Te extraño','fr':'Tu me manques'},
      'interaction_infinity': {'tr':'Sonsuza kadar','en':'Forever','de':'Für immer','es':'Para siempre','fr':'Pour toujours'},
      'interaction': {'tr':'Etkileşim','en':'Interaction','de':'Interaktion','es':'Interacción','fr':'Interaction'},
      'pet_room_play': {'tr':'Oyun','en':'Play','de':'Spiel','es':'Juego','fr':'Jeu'},
      'pet_room_care': {'tr':'Bakım','en':'Care','de':'Pflege','es':'Cuidado','fr':'Soin'},
      'pet_room_sleep': {'tr':'Uyku','en':'Sleep','de':'Schlaf','es':'Sueño','fr':'Sommeil'},
      'pet_room_food': {'tr':'Mama','en':'Food','de':'Futter','es':'Comida','fr':'Nourriture'},
      'mood_history_failed': {'tr':'Ruh hali geçmişi yüklenemedi.','en':'Mood history could not be loaded.','de':'Stimmungsverlauf konnte nicht geladen werden.','es':'No se pudo cargar el historial de ánimo.','fr':'Impossible de charger l’historique de l’humeur.'},
      'check_database': {'tr':'Veritabanı bağlantısını kontrol edin.','en':'Check the database connection.','de':'Prüfe die Datenbankverbindung.','es':'Comprueba la conexión de la base de datos.','fr':'Vérifiez la connexion à la base de données.'},
      'last_30_days': {'tr':'Son 30 gün','en':'Last 30 days','de':'Letzte 30 Tage','es':'Últimos 30 días','fr':'30 derniers jours'},
      'average': {'tr':'Ortalama','en':'Average','de':'Durchschnitt','es':'Promedio','fr':'Moyenne'},
      'highest': {'tr':'En iyi','en':'Highest','de':'Höchster Wert','es':'Máximo','fr':'Maximum'},
      'entries': {'tr':'Kayıt','en':'Entries','de':'Einträge','es':'Registros','fr':'Entrées'},
      'how_are_you': {'tr':'Bugün nasılsın?','en':'How are you today?','de':'Wie geht es dir heute?','es':'¿Cómo estás hoy?','fr':'Comment allez-vous aujourd’hui ?'},
      'category_general': {'tr':'Genel','en':'General','de':'Allgemein','es':'General','fr':'Général'},
      'category_relationship': {'tr':'İlişki','en':'Relationship','de':'Beziehung','es':'Relación','fr':'Relation'},
      'category_work': {'tr':'İş','en':'Work','de':'Arbeit','es':'Trabajo','fr':'Travail'},
      'category_health': {'tr':'Sağlık','en':'Health','de':'Gesundheit','es':'Salud','fr':'Santé'},
      'category_family': {'tr':'Aile','en':'Family','de':'Familie','es':'Familia','fr':'Famille'},
      'note_optional': {'tr':'Not ekle (opsiyonel)','en':'Add a note (optional)','de':'Notiz hinzufügen (optional)','es':'Añadir una nota (opcional)','fr':'Ajouter une note (facultatif)'},
      'mood_saved': {'tr':'Ruh hali kaydedildi! ✅','en':'Mood saved! ✅','de':'Stimmung gespeichert! ✅','es':'¡Ánimo guardado! ✅','fr':'Humeur enregistrée ! ✅'},
      'save': {'tr':'Kaydet','en':'Save','de':'Speichern','es':'Guardar','fr':'Enregistrer'},
      'cancel_action': {'tr':'İptal','en':'Cancel','de':'Abbrechen','es':'Cancelar','fr':'Annuler'},
      'send_now': {'tr':'Hemen gönder','en':'Send now','de':'Jetzt senden','es':'Enviar ahora','fr':'Envoyer maintenant'},
      'schedule_send': {'tr':'Gönderilecek: {date}','en':'Scheduled: {date}','de':'Geplant: {date}','es':'Programado: {date}','fr':'Planifié : {date}'},
      'remove_schedule': {'tr':'Zamanlamayı kaldır','en':'Remove schedule','de':'Planung entfernen','es':'Quitar programación','fr':'Supprimer la planification'},
      'letter_time_future': {'tr':'Mektup zamanı gelecekte olmalı.','en':'The letter time must be in the future.','de':'Die Briefzeit muss in der Zukunft liegen.','es':'La hora de la carta debe estar en el futuro.','fr':'La date de la lettre doit être dans le futur.'},
      'letter_empty': {'tr':'Mektup boş olamaz.','en':'The letter cannot be empty.','de':'Der Brief darf nicht leer sein.','es':'La carta no puede estar vacía.','fr':'La lettre ne peut pas être vide.'},
      'letters_failed': {'tr':'Mektuplar yüklenemedi.','en':'Letters could not be loaded.','de':'Briefe konnten nicht geladen werden.','es':'No se pudieron cargar las cartas.','fr':'Impossible de charger les lettres.'},
      'no_letters': {'tr':'Henüz mektup yok 💌','en':'No letters yet 💌','de':'Noch keine Briefe 💌','es':'Aún no hay cartas 💌','fr':'Aucune lettre pour le moment 💌'},
      'new_letter': {'tr':'Yeni mektup','en':'New letter','de':'Neuer Brief','es':'Nueva carta','fr':'Nouvelle lettre'},
      'write_letter': {'tr':'Mektubunu yaz...','en':'Write your letter...','de':'Schreibe deinen Brief...','es':'Escribe tu carta...','fr':'Écrivez votre lettre...'},
      'close': {'tr':'Kapat','en':'Close','de':'Schließen','es':'Cerrar','fr':'Fermer'},
      'countdown_title': {'tr':'Geri sayımlar','en':'Countdowns','de':'Countdowns','es':'Cuentas atrás','fr':'Comptes à rebours'},
      'no_countdowns': {'tr':'Henüz geri sayım yok','en':'No countdowns yet','de':'Noch keine Countdowns','es':'Aún no hay cuentas atrás','fr':'Aucun compte à rebours'},
      'countdown_finished': {'tr':'Bitti!','en':'Finished!','de':'Fertig!','es':'¡Terminado!','fr':'Terminé !'},
      'days_left': {'tr':'gün kaldı','en':'days left','de':'Tage übrig','es':'días restantes','fr':'jours restants'},
      'new_countdown': {'tr':'Yeni geri sayım','en':'New countdown','de':'Neuer Countdown','es':'Nueva cuenta atrás','fr':'Nouveau compte à rebours'},
      'countdown_delete_failed': {'tr':'Geri sayım silinemedi','en':'Could not delete countdown','de':'Countdown konnte nicht gelöscht werden','es':'No se pudo eliminar la cuenta atrás','fr':'Impossible de supprimer le compte à rebours'},
      'countdown_data_failed': {'tr':'Geri sayım verileri yüklenemedi.','en':'Could not load countdown data.','de':'Countdown-Daten konnten nicht geladen werden.','es':'No se pudieron cargar los datos.','fr':'Impossible de charger les données.'},
      'check_premium_tables': {'tr':'Veritabanı bağlantısını ve premium tablolarını kontrol edin.','en':'Check the database connection and premium tables.','de':'Prüfe die Datenbankverbindung und Premium-Tabellen.','es':'Comprueba la conexión y las tablas premium.','fr':'Vérifiez la connexion et les tables premium.'},
      'headline': {'tr':'Başlık','en':'Title','de':'Titel','es':'Título','fr':'Titre'},
      'visit': {'tr':'Ziyaret ✈️','en':'Visit ✈️','de':'Besuch ✈️','es':'Visita ✈️','fr':'Visite ✈️'},
      'anniversary': {'tr':'Yıldönümü 💑','en':'Anniversary 💑','de':'Jahrestag 💑','es':'Aniversario 💑','fr':'Anniversaire 💑'},
      'birthday': {'tr':'Doğum günü 🎂','en':'Birthday 🎂','de':'Geburtstag 🎂','es':'Cumpleaños 🎂','fr':'Anniversaire 🎂'},
      'custom': {'tr':'Özel 📅','en':'Custom 📅','de':'Benutzerdefiniert 📅','es':'Personalizado 📅','fr':'Personnalisé 📅'},
      'select_date': {'tr':'Tarih seç','en':'Select date','de':'Datum auswählen','es':'Seleccionar fecha','fr':'Choisir une date'},
      'fill_all_fields': {'tr':'Lütfen tüm alanları doldurun','en':'Please fill in all fields','de':'Bitte alle Felder ausfüllen','es':'Completa todos los campos','fr':'Veuillez remplir tous les champs'},
      'mood_best': {'tr':'En iyi','en':'Best','de':'Am besten','es':'Mejor','fr':'Meilleur'},
      'letter_cancel': {'tr':'İptal','en':'Cancel','de':'Abbrechen','es':'Cancelar','fr':'Annuler'},
      'letter_empty_error': {'tr':'Mektup boş olamaz.','en':'The letter cannot be empty.','de':'Der Brief darf nicht leer sein.','es':'La carta no puede estar vacía.','fr':'La lettre ne peut pas être vide.'},
      'no_letters_yet': {'tr':'Henüz mektup yok 💌','en':'No letters yet 💌','de':'Noch keine Briefe 💌','es':'Aún no hay cartas 💌','fr':'Aucune lettre pour le moment 💌'},
      'write_letter_hint': {'tr':'Mektubunu yaz...','en':'Write your letter...','de':'Schreibe deinen Brief...','es':'Escribe tu carta...','fr':'Écrivez votre lettre...'},
      'scheduled_remove': {'tr':'Zamanlamayı kaldır','en':'Remove schedule','de':'Planung entfernen','es':'Quitar programación','fr':'Supprimer la planification'},
      'letter_send': {'tr':'Gönder','en':'Send','de':'Senden','es':'Enviar','fr':'Envoyer'},
      'letter_scheduled': {'tr':'Mektup zamanlandı 💌','en':'Letter scheduled 💌','de':'Brief geplant 💌','es':'Carta programada 💌','fr':'Lettre planifiée 💌'},
      'letter_sent': {'tr':'Mektup gönderildi 💌','en':'Letter sent 💌','de':'Brief gesendet 💌','es':'Carta enviada 💌','fr':'Lettre envoyée 💌'},
      'letter_send_failed': {'tr':'Mektup gönderilemedi','en':'Could not send letter','de':'Brief konnte nicht gesendet werden','es':'No se pudo enviar la carta','fr':'Impossible d’envoyer la lettre'},
      'sender': {'tr':'Gönderen','en':'Sender','de':'Absender','es':'Remitente','fr':'Expéditeur'},
      'date': {'tr':'Tarih','en':'Date','de':'Datum','es':'Fecha','fr':'Date'},
      'sent_letter': {'tr':'Gönderdiğin mektup','en':'Letter you sent','de':'Dein gesendeter Brief','es':'Carta que enviaste','fr':'Lettre envoyée'},
      'received_letter': {'tr':'Sana gelen mektup','en':'Letter you received','de':'Erhaltener Brief','es':'Carta recibida','fr':'Lettre reçue'},
      'score': {'tr':'Puan','en':'Score','de':'Punkte','es':'Puntuación','fr':'Score'},
      'question': {'tr':'Soru','en':'Question','de':'Frage','es':'Pregunta','fr':'Question'},
      'game_over': {'tr':'Oyun bitti!','en':'Game over!','de':'Spiel vorbei!','es':'¡Fin del juego!','fr':'Partie terminée !'},
      'done': {'tr':'Tamam','en':'Done','de':'Fertig','es':'Listo','fr':'Terminé'},
      'success': {'tr':'Başarı','en':'Success','de':'Erfolg','es':'Éxito','fr':'Réussite'},
    };
    final map = values[key];
    if (map == null) return key;
    return map[code] ?? map['en'] ?? key;
  }

  String get chat => _t({'tr':'Sohbet','en':'Chat','de':'Chat','es':'Chat','fr':'Chat'});
  String get pet => _t({'tr':'Pet','en':'Pet','de':'Haustier','es':'Mascota','fr':'Animal'});
  String get games => _t({'tr':'Oyunlar','en':'Games','de':'Spiele','es':'Juegos','fr':'Jeux'});
  String get relationship => _t({'tr':'Özel','en':'Special','de':'Besonders','es':'Especial','fr':'Spécial'});
  String get theme => _t({'tr':'Tema Ayarları','en':'Theme Settings','de':'Theme-Einstellungen','es':'Ajustes de tema','fr':'Réglages du thème'});
  String get profile => _t({'tr':'Profil','en':'Profile','de':'Profil','es':'Perfil','fr':'Profil'});
  String get logout => _t({'tr':'Çıkış Yap','en':'Log out','de':'Abmelden','es':'Cerrar sesión','fr':'Se déconnecter'});

  String get todo => _t({'tr':'Görevler','en':'Tasks','de':'Aufgaben','es':'Tareas','fr':'Tâches'});
  String get map => _t({'tr':'Harita','en':'Map','de':'Karte','es':'Mapa','fr':'Carte'});
  String get callHistory => _t({'tr':'Arama Geçmişi','en':'Call History','de':'Anrufverlauf','es':'Historial de llamadas','fr':'Historique des appels'});
  String get notifications => _t({'tr':'Bildirimler','en':'Notifications','de':'Benachrichtigungen','es':'Notificaciones','fr':'Notifications'});
  String get interactions => _t({'tr':'Etkileşimler','en':'Interactions','de':'Interaktionen','es':'Interacciones','fr':'Interactions'});
  String get gameMostLikely => _t({'tr':'Most Likely To','en':'Most Likely To','de':'Wer würde eher?','es':'Quién es más probable','fr':'Qui est le plus susceptible'});
  String get gameTrivia => _t({'tr':'Trivia','en':'Trivia','de':'Quiz','es':'Trivia','fr':'Quiz'});
  String get gameWord => _t({'tr':'Kelime Oyunu','en':'Word Chain','de':'Wortkette','es':'Cadena de palabras','fr':'Chaîne de mots'});
  String get conversationFinder => t('conversation_finder');
  String get conversationFinderSubtitle => t('conversation_finder_subtitle');
  String get conversationTopics => t('conversation_topics');
  String get jokes => t('jokes');
  String get markAsAsked => t('mark_as_asked');
  String get asked => t('asked');
  String get answerOptional => t('answer_optional');
  String get addYourOwnTopic => t('add_your_own_topic');
  String get topicQuestion => t('topic_question');
  String get answer => t('answer');
  String get topicAdded => t('topic_added');
  String get topicSaveFailed => t('topic_save_failed');
  String get topicsLoadFailed => t('topics_load_failed');
  String get noTopics => t('no_topics');

  String get relationshipHub => _t({'tr':'Birlikte','en':'Together','de':'Gemeinsam','es':'Juntos','fr':'Ensemble'});
  String get relationshipHubSubtitle => _t({
    'tr':'İkiniz için önemli anları ve küçük ritüelleri tek yerde tutun.',
    'en':'Keep your important moments and little rituals together in one place.',
    'de':'Bewahrt eure wichtigen Momente und kleinen Rituale an einem Ort auf.',
    'es':'Guarden sus momentos importantes y pequeños rituales en un solo lugar.',
    'fr':'Gardez vos moments importants et vos petits rituels au même endroit.',
  });
  String get countdown => _t({'tr':'Geri Sayım','en':'Countdown','de':'Countdown','es':'Cuenta atrás','fr':'Compte à rebours'});
  String get countdownSubtitle => _t({'tr':'Özel gününüze kalan süre','en':'Time left until your special day','de':'Zeit bis zu eurem besonderen Tag','es':'Tiempo hasta vuestro día especial','fr':'Temps restant avant votre jour spécial'});
  String get mood => _t({'tr':'Ruh Halim','en':'My Mood','de':'Meine Stimmung','es':'Mi estado de ánimo','fr':'Mon humeur'});
  String get moodSubtitle => _t({'tr':'Bugün nasıl hissettiğini paylaş','en':'Share how you feel today','de':'Teile, wie du dich heute fühlst','es':'Comparte cómo te sientes hoy','fr':'Partagez votre humeur du jour'});
  String get loveLetters => _t({'tr':'Mektup','en':'Letters','de':'Briefe','es':'Cartas','fr':'Lettres'});
  String get loveLettersSubtitle => _t({'tr':'Partnerine gönderdiğin ve ondan aldığın mektuplar','en':'Letters you send and receive from your partner','de':'Briefe, die ihr euch schickt','es':'Cartas que se envían entre ustedes','fr':'Les lettres que vous vous envoyez'});
  String get open => _t({'tr':'Aç','en':'Open','de':'Öffnen','es':'Abrir','fr':'Ouvrir'});
  String get togetherTag => _t({'tr':'Sadece ikiniz','en':'Just the two of you','de':'Nur ihr zwei','es':'Solo ustedes dos','fr':'Juste vous deux'});

  String get signIn => _t({'tr':'Giriş Yap','en':'Sign In','de':'Anmelden','es':'Iniciar sesión','fr':'Se connecter'});
  String get signUp => _t({'tr':'Kaydol','en':'Sign Up','de':'Registrieren','es':'Registrarse','fr':'S’inscrire'});
  String get email => _t({'tr':'E-posta','en':'Email','de':'E-Mail','es':'Correo electrónico','fr':'E-mail'});
  String get password => _t({'tr':'Şifre','en':'Password','de':'Passwort','es':'Contraseña','fr':'Mot de passe'});
  String get username => _t({'tr':'Kullanıcı adı','en':'Username','de':'Benutzername','es':'Nombre de usuario','fr':'Nom d’utilisateur'});
  String get invalidCredentials => _t({'tr':'E-posta ve şifre gerekli','en':'Email and password are required','de':'E-Mail und Passwort sind erforderlich','es':'Se requieren correo y contraseña','fr':'E-mail et mot de passe requis'});
  String get loginFailed => _t({'tr':'Giriş başarısız','en':'Sign in failed','de':'Anmeldung fehlgeschlagen','es':'Error al iniciar sesión','fr':'Échec de connexion'});
  String get noAccount => _t({'tr':'Hesabın yok mu?','en':'Don’t have an account?','de':'Noch kein Konto?','es':'¿No tienes una cuenta?','fr':'Pas encore de compte ?'});
  String get alreadyAccount => _t({'tr':'Zaten hesabın var mı?','en':'Already have an account?','de':'Du hast bereits ein Konto?','es':'¿Ya tienes una cuenta?','fr':'Vous avez déjà un compte ?'});
  String get fillAllFields => _t({'tr':'Tüm alanları doldurun','en':'Please fill in all fields','de':'Bitte alle Felder ausfüllen','es':'Completa todos los campos','fr':'Veuillez remplir tous les champs'});
  String get notificationsLoadFailed => _t({'tr':'Bildirimler yüklenemedi.','en':'Could not load notifications.','de':'Benachrichtigungen konnten nicht geladen werden.','es':'No se pudieron cargar las notificaciones.','fr':'Impossible de charger les notifications.'});
  String get noNotifications => _t({'tr':'Henüz bildirim yok.','en':'No notifications yet.','de':'Noch keine Benachrichtigungen.','es':'Aún no hay notificaciones.','fr':'Aucune notification pour le moment.'});
  String get markAllRead => _t({'tr':'Tümünü oku','en':'Mark all as read','de':'Alle als gelesen markieren','es':'Marcar todo como leído','fr':'Tout marquer comme lu'});
  String get interactionHistory => _t({'tr':'Etkileşim Geçmişi','en':'Interaction History','de':'Interaktionsverlauf','es':'Historial de interacciones','fr':'Historique des interactions'});
  String get noInteractions => _t({'tr':'Henüz bir etkileşim yok 💕','en':'No interactions yet 💕','de':'Noch keine Interaktionen 💕','es':'Aún no hay interacciones 💕','fr':'Aucune interaction pour le moment 💕'});
  String get sharedMedia => _t({'tr':'Paylaşılan görseller','en':'Shared media','de':'Geteilte Medien','es':'Medios compartidos','fr':'Médias partagés'});
  String get noSharedMedia => _t({'tr':'Henüz paylaşılan medya yok','en':'No shared media yet','de':'Noch keine geteilten Medien','es':'Aún no hay medios compartidos','fr':'Aucun média partagé pour le moment'});
  String get online => _t({'tr':'Çevrimiçi','en':'Online','de':'Online','es':'En línea','fr':'En ligne'});
  String get away => _t({'tr':'Uzakta','en':'Away','de':'Abwesend','es':'Ausente','fr':'Absent'});
  String get offline => _t({'tr':'Çevrimdışı','en':'Offline','de':'Offline','es':'Sin conexión','fr':'Hors ligne'});
  String get tasks => _t({'tr':'Görevler','en':'Tasks','de':'Aufgaben','es':'Tareas','fr':'Tâches'});
  String get call => _t({'tr':'Ara','en':'Call','de':'Anrufen','es':'Llamar','fr':'Appeler'});
  String get send => _t({'tr':'Gönder','en':'Send','de':'Senden','es':'Enviar','fr':'Envoyer'});
  String get media => _t({'tr':'Görsel veya video','en':'Photo or video','de':'Foto oder Video','es':'Foto o vídeo','fr':'Photo ou vidéo'});
  String get chooseImage => _t({'tr':'Görsel seç','en':'Choose photo','de':'Foto auswählen','es':'Elegir foto','fr':'Choisir une photo'});
  String get chooseVideo => _t({'tr':'Video seç','en':'Choose video','de':'Video auswählen','es':'Elegir vídeo','fr':'Choisir une vidéo'});
  String get newTask => _t({'tr':'Yeni görev...','en':'New task...','de':'Neue Aufgabe...','es':'Nueva tarea...','fr':'Nouvelle tâche...'});
  String get mapSubtitle => _t({'tr':'Birlikte kaydettiğiniz ve keşfettiğiniz yerler','en':'Places you saved and explored together','de':'Orte, die ihr zusammen gespeichert und entdeckt habt','es':'Lugares que han guardado y explorado juntos','fr':'Lieux que vous avez enregistrés et explorés ensemble'});
  String get pairFirst => _t({'tr':'Önce partnerinle eşleşmelisin.','en':'Pair with your partner first.','de':'Verbinde dich zuerst mit deinem Partner.','es':'Primero vincúlate con tu pareja.','fr':'Associez-vous d’abord à votre partenaire.'});
  String get pair => _t({'tr':'Partner ile Eşleş','en':'Pair with Partner','de':'Mit Partner verbinden','es':'Vincular con tu pareja','fr':'Associer votre partenaire'});
  String get pairingCode => _t({'tr':'Eşleşme kodun','en':'Pairing code','de':'Paarungscode','es':'Código de pareja','fr':'Code de jumelage'});
  String get countrySelect => _t({'tr':'Ülke seç','en':'Select country','de':'Land auswählen','es':'Seleccionar país','fr':'Choisir un pays'});
  String get regionSelect => _t({'tr':'İl / eyalet / bölge','en':'State / region','de':'Bundesland / Region','es':'Estado / región','fr':'État / région'});
  String get citySelect => _t({'tr':'Şehir / yerleşim','en':'City / locality','de':'Stadt / Ort','es':'Ciudad / localidad','fr':'Ville / localité'});
  String get searchCountry => _t({'tr':'Ülke adı veya ISO kodu ara','en':'Search country name or ISO code','de':'Ländername oder ISO-Code suchen','es':'Buscar nombre de país o código ISO','fr':'Rechercher un pays ou un code ISO'});
  String get searchCity => _t({'tr':'Şehir adını yaz...','en':'Search city...','de':'Stadt suchen...','es':'Buscar ciudad...','fr':'Rechercher une ville...'});
  String get noCountries => _t({'tr':'Ülke bulunamadı.','en':'No countries found.','de':'Keine Länder gefunden.','es':'No se encontraron países.','fr':'Aucun pays trouvé.'});
  String get noRegions => _t({'tr':'Bölge bulunamadı.','en':'No regions found.','de':'Keine Regionen gefunden.','es':'No se encontraron regiones.','fr':'Aucune région trouvée.'});
  String get noCities => _t({'tr':'Şehir bulunamadı.','en':'No cities found.','de':'Keine Städte gefunden.','es':'No se encontraron ciudades.','fr':'Aucune ville trouvée.'});
  String get close => _t({'tr':'Kapat','en':'Close','de':'Schließen','es':'Cerrar','fr':'Fermer'});
  String get delete => _t({'tr':'Sil','en':'Delete','de':'Löschen','es':'Eliminar','fr':'Supprimer'});
  String get cancel => _t({'tr':'Vazgeç','en':'Cancel','de':'Abbrechen','es':'Cancelar','fr':'Annuler'});
  String get save => _t({'tr':'Kaydet','en':'Save','de':'Speichern','es':'Guardar','fr':'Enregistrer'});
  String get themeSettings => _t({'tr':'Tema Ayarları','en':'Theme Settings','de':'Theme-Einstellungen','es':'Ajustes de tema','fr':'Réglages du thème'});
  String get darkTheme => _t({'tr':'Koyu tema','en':'Dark theme','de':'Dunkles Design','es':'Tema oscuro','fr':'Thème sombre'});
  String get language => _t({'tr':'Dil','en':'Language','de':'Sprache','es':'Idioma','fr':'Langue'});
  String get color => _t({'tr':'Renk','en':'Color','de':'Farbe','es':'Color','fr':'Couleur'});

  String get error => _t({'tr':'Hata','en':'Error','de':'Fehler','es':'Error','fr':'Erreur'});
  String get newAccount => _t({'tr':'Yeni Hesap','en':'New Account','de':'Neues Konto','es':'Nueva cuenta','fr':'Nouveau compte'});
  String get usernameLengthHelp => _t({'tr':'3-20 karakter','en':'3-20 characters','de':'3–20 Zeichen','es':'3–20 caracteres','fr':'3–20 caractères'});
  String get passwordLengthHelp => _t({'tr':'En az 6 karakter','en':'At least 6 characters','de':'Mindestens 6 Zeichen','es':'Al menos 6 caracteres','fr':'Au moins 6 caractères'});
  String get usernameInvalid => _t({'tr':'Kullanıcı adı 3-20 karakter olmalı','en':'Username must be 3-20 characters','de':'Der Benutzername muss 3–20 Zeichen lang sein','es':'El nombre de usuario debe tener 3–20 caracteres','fr':'Le nom d’utilisateur doit comporter 3 à 20 caractères'});
  String get emailInvalid => _t({'tr':'Geçerli bir e-posta adresi girin','en':'Enter a valid email address','de':'Gib eine gültige E-Mail-Adresse ein','es':'Introduce una dirección de correo válida','fr':'Saisissez une adresse e-mail valide'});
  String get passwordInvalid => _t({'tr':'Şifre en az 6 karakter','en':'Password must be at least 6 characters','de':'Das Passwort muss mindestens 6 Zeichen lang sein','es':'La contraseña debe tener al menos 6 caracteres','fr':'Le mot de passe doit comporter au moins 6 caractères'});
  String get signupFailed => _t({'tr':'Kayıt başarısız','en':'Sign up failed','de':'Registrierung fehlgeschlagen','es':'Error al registrarse','fr':'Échec de l’inscription'});
  String get profileUpdated => _t({'tr':'Profil güncellendi.','en':'Profile updated.','de':'Profil aktualisiert.','es':'Perfil actualizado.','fr':'Profil mis à jour.'});
  String get profileUpdateFailed => _t({'tr':'Profil güncellenemedi.','en':'Could not update profile.','de':'Profil konnte nicht aktualisiert werden.','es':'No se pudo actualizar el perfil.','fr':'Impossible de mettre à jour le profil.'});
  String get photoUpdated => _t({'tr':'Profil fotoğrafı güncellendi.','en':'Profile photo updated.','de':'Profilfoto aktualisiert.','es':'Foto de perfil actualizada.','fr':'Photo de profil mise à jour.'});
  String get photoUploadFailed => _t({'tr':'Fotoğraf yüklenemedi.','en':'Could not upload photo.','de':'Foto konnte nicht hochgeladen werden.','es':'No se pudo subir la foto.','fr':'Impossible de téléverser la photo.'});
  String get photoSelectFailed => _t({'tr':'Fotoğraf seçilemedi.','en':'Could not select a photo.','de':'Foto konnte nicht ausgewählt werden.','es':'No se pudo seleccionar la foto.','fr':'Impossible de sélectionner une photo.'});
  String get status => _t({'tr':'Durum','en':'Status','de':'Status','es':'Estado','fr':'Statut'});
  String get codeCopied => _t({'tr':'Kod kopyalandı.','en':'Code copied.','de':'Code kopiert.','es':'Código copiado.','fr':'Code copié.'});
  String get chatLoadFailed => _t({'tr':'Sohbet yüklenemedi','en':'Could not load chat','de':'Chat konnte nicht geladen werden','es':'No se pudo cargar el chat','fr':'Impossible de charger le chat'});
  String get checkConnection => _t({'tr':'Bağlantıyı kontrol edip tekrar deneyin.','en':'Check your connection and try again.','de':'Prüfe deine Verbindung und versuche es erneut.','es':'Comprueba tu conexión e inténtalo de nuevo.','fr':'Vérifiez votre connexion et réessayez.'});
  String get noMessages => _t({'tr':'Henüz mesaj yok','en':'No messages yet','de':'Noch keine Nachrichten','es':'Aún no hay mensajes','fr':'Aucun message pour le moment'});
  String get firstMessage => _t({'tr':'İlk mesajı sen gönder ve sohbeti başlat 💕','en':'Send the first message and start the conversation 💕','de':'Sende die erste Nachricht und startet das Gespräch 💕','es':'Envía el primer mensaje y empieza la conversación 💕','fr':'Envoyez le premier message et démarrez la conversation 💕'});
  String get messageHint => _t({'tr':'Mesaj yaz...','en':'Write a message...','de':'Nachricht schreiben...','es':'Escribe un mensaje...','fr':'Écrire un message...'});
  String get searchMedia => _t({'tr':'Görsel veya video','en':'Photo or video','de':'Foto oder Video','es':'Foto o vídeo','fr':'Photo ou vidéo'});
  String get sendToPartner => _t({'tr':'Partnerine gönder','en':'Send to your partner','de':'An deinen Partner senden','es':'Enviar a tu pareja','fr':'Envoyer à votre partenaire'});
  String get sent => _t({'tr':'gönderildi','en':'sent','de':'gesendet','es':'enviado','fr':'envoyé'});
  String get sendFailed => _t({'tr':'Gönderilemedi','en':'Could not send','de':'Senden fehlgeschlagen','es':'No se pudo enviar','fr':'Envoi impossible'});
  String get mediaSendFailed => _t({'tr':'Medya gönderilemedi','en':'Could not send media','de':'Medien konnten nicht gesendet werden','es':'No se pudo enviar el medio','fr':'Impossible d’envoyer le média'});
  String get callFailed => _t({'tr':'Arama başlatılamadı','en':'Could not start call','de':'Anruf konnte nicht gestartet werden','es':'No se pudo iniciar la llamada','fr':'Impossible de démarrer l’appel'});
  String get select => _t({'tr':'Seç','en':'Select','de':'Auswählen','es':'Seleccionar','fr':'Sélectionner'});
  String get selections => _t({'tr':'Seçimler','en':'Selections','de':'Auswahlen','es':'Selecciones','fr':'Sélections'});
  String get help => _t({'tr':'Yardım','en':'Help','de':'Hilfe','es':'Ayuda','fr':'Aide'});
  String get you => _t({'tr':'Sen','en':'You','de':'Du','es':'Tú','fr':'Vous'});
  String get partner => _t({'tr':'Partner','en':'Partner','de':'Partner','es':'Pareja','fr':'Partenaire'});
  String get together => _t({'tr':'İkiniz','en':'Both','de':'Beide','es':'Ambos','fr':'Tous les deux'});
  String get selectedPlaces => _t({'tr':'Seçilen yerler','en':'Selected places','de':'Ausgewählte Orte','es':'Lugares seleccionados','fr':'Lieux sélectionnés'});
  String get noSavedPlaces => _t({'tr':'Henüz kayıtlı yer yok.','en':'No saved places yet.','de':'Noch keine Orte gespeichert.','es':'Aún no hay lugares guardados.','fr':'Aucun lieu enregistré pour le moment.'});
  String get saveCountryFirst => _t({'tr':'Önce bir ülke seç.','en':'Select a country first.','de':'Wähle zuerst ein Land.','es':'Selecciona primero un país.','fr':'Sélectionnez d’abord un pays.'});
  String get stateOrRegionHint => _t({'tr':'Örn. Nevşehir, California, Bavaria...','en':'E.g. California, Bavaria, Île-de-France...','de':'Z. B. Bayern, Kalifornien...','es':'P. ej. California, Baviera...','fr':'Ex. Californie, Bavière...'});
  String get cityHint => _t({'tr':'Örn. Nevşehir, Acıgöl, Ürgüp...','en':'E.g. London, Austin, Kyoto...','de':'Z. B. Berlin, München...','es':'P. ej. Madrid, Valencia...','fr':'Ex. Paris, Lyon...'});
  String get backToRegions => _t({'tr':'Bölgelere dön','en':'Back to regions','de':'Zurück zu Regionen','es':'Volver a regiones','fr':'Retour aux régions'});
  String get locationDataFailed => _t({'tr':'Konum verisi yüklenemedi','en':'Could not load location data','de':'Standortdaten konnten nicht geladen werden','es':'No se pudieron cargar los datos de ubicación','fr':'Impossible de charger les données de localisation'});
  String get deleteThisSelection => _t({'tr':'Bu yeri sil','en':'Delete this place','de':'Diesen Ort löschen','es':'Eliminar este lugar','fr':'Supprimer ce lieu'});
  String get deleteSelectionTitle => _t({'tr':'Seçimi sil?','en':'Delete selection?','de':'Auswahl löschen?','es':'¿Eliminar selección?','fr':'Supprimer la sélection ?'});
  String get deleteSelectionConfirm => _t({'tr':'Bu seçimi silmek istediğine emin misin?','en':'Are you sure you want to delete this selection?','de':'Möchtest du diese Auswahl wirklich löschen?','es':'¿Seguro que quieres eliminar esta selección?','fr':'Voulez-vous vraiment supprimer cette sélection ?'});
  String get mediaShared => _t({'tr':'Paylaşılan görseller','en':'Shared images','de':'Geteilte Bilder','es':'Imágenes compartidas','fr':'Images partagées'});

  String get incomingCall => _t({'tr':'Gelen arama','en':'Incoming call','de':'Eingehender Anruf','es':'Llamada entrante','fr':'Appel entrant'});
  String get accept => _t({'tr':'Kabul et','en':'Accept','de':'Annehmen','es':'Aceptar','fr':'Accepter'});
  String get decline => _t({'tr':'Reddet','en':'Decline','de':'Ablehnen','es':'Rechazar','fr':'Refuser'});
  String get startCall => _t({'tr':'Aramayı başlat','en':'Start call','de':'Anruf starten','es':'Iniciar llamada','fr':'Démarrer l’appel'});
  String get pairingFailed => _t({'tr':'Eşleşme başarısız','en':'Pairing failed','de':'Kopplung fehlgeschlagen','es':'Error de vinculación','fr':'Échec du jumelage'});

  String get lightTheme => _t({'tr':'Açık','en':'Light','de':'Hell','es':'Claro','fr':'Clair'});
  String get profileUnavailable => _t({'tr':'Profil kullanılamıyor.','en':'Profile unavailable.','de':'Profil nicht verfügbar.','es':'Perfil no disponible.','fr':'Profil indisponible.'});
  String get copy => _t({'tr':'Kopyala','en':'Copy','de':'Kopieren','es':'Copiar','fr':'Copier'});
  String get myCode => _t({'tr':'Senin kodun','en':'Your code','de':'Dein Code','es':'Tu código','fr':'Votre code'});
  String get pairingAlreadyDone => _t({'tr':'Zaten eşleştiniz ❤️','en':'You are already paired ❤️','de':'Ihr seid bereits verbunden ❤️','es':'Ya están vinculados ❤️','fr':'Vous êtes déjà jumelés ❤️'});
  String get pairingAlreadyDescription => _t({'tr':'Bu hesap zaten bir partnerle eşleşmiş durumda.','en':'This account is already paired with a partner.','de':'Dieses Konto ist bereits mit einem Partner verbunden.','es':'Esta cuenta ya está vinculada con una pareja.','fr':'Ce compte est déjà associé à un partenaire.'});
  String get backHome => _t({'tr':'Ana sayfaya dön','en':'Back to home','de':'Zur Startseite','es':'Volver al inicio','fr':'Retour à l’accueil'});
  String get shareCodeHint => _t({'tr':'Bu kodu partnerinle paylaş ve onun kodunu buraya gir.','en':'Share this code with your partner and enter their code here.','de':'Teile diesen Code mit deinem Partner und gib hier seinen Code ein.','es':'Comparte este código con tu pareja e introduce el suyo aquí.','fr':'Partagez ce code avec votre partenaire et saisissez le sien ici.'});
  String get invalidPairCode => _t({'tr':'6 haneli kod gerekli','en':'A 6-digit code is required','de':'Ein 6-stelliger Code ist erforderlich','es':'Se requiere un código de 6 dígitos','fr':'Un code à 6 chiffres est requis'});

  String get partnerProfile => _t({'tr':'Partner profili','en':'Partner profile','de':'Partnerprofil','es':'Perfil de pareja','fr':'Profil du partenaire'});
  String get shared => _t({'tr':'Paylaşılan','en':'Shared','de':'Geteilt','es':'Compartido','fr':'Partagé'});
  String get tryAgain => _t({'tr':'Tekrar dene','en':'Try again','de':'Erneut versuchen','es':'Reintentar','fr':'Réessayer'});
  String get errorLoading => _t({'tr':'Yüklenemedi','en':'Could not load','de':'Laden fehlgeschlagen','es':'No se pudo cargar','fr':'Impossible de charger'});
  String get viewProfile => _t({'tr':'Profili görüntüle','en':'View profile','de':'Profil ansehen','es':'Ver perfil','fr':'Voir le profil'});

  String get acceptToStartCall => _t({'tr':'Aramayı başlatmak için kabul et','en':'Accept to start the call','de':'Annehmen, um den Anruf zu starten','es':'Acepta para iniciar la llamada','fr':'Acceptez pour démarrer l’appel'});
  String get pairTogetherPrompt => _t({'tr':'Bestie alanını birlikte kullanmaya başlayın','en':'Start using Bestie together','de':'Startet gemeinsam mit Bestie','es':'Empiecen a usar Bestie juntos','fr':'Commencez à utiliser Bestie ensemble'});
  String get noTasks => _t({'tr':'Henüz görev yok','en':'No tasks yet','de':'Noch keine Aufgaben','es':'Aún no hay tareas','fr':'Aucune tâche pour le moment'});
  String get noSharedMediaYet => _t({'tr':'Henüz paylaşılan medya yok','en':'No shared media yet','de':'Noch keine geteilten Medien','es':'Aún no hay medios compartidos','fr':'Aucun média partagé pour le moment'});
  String get moodTerrible => _t({'tr':'Çok kötü','en':'Very bad','de':'Sehr schlecht','es':'Muy mal','fr':'Très mal'});
  String get moodBad => _t({'tr':'Kötü','en':'Bad','de':'Schlecht','es':'Mal','fr':'Mauvais'});
  String get moodOkay => _t({'tr':'Normal','en':'Okay','de':'Normal','es':'Normal','fr':'Normal'});
  String get moodGood => _t({'tr':'İyi','en':'Good','de':'Gut','es':'Bien','fr':'Bien'});
  String get moodAmazing => _t({'tr':'Harika','en':'Amazing','de':'Großartig','es':'Genial','fr':'Génial'});
  String get moodNone => _t({'tr':'Mod yok','en':'No mood','de':'Keine Stimmung','es':'Sin estado de ánimo','fr':'Aucune humeur'});
  String get hug => _t({'tr':'Sarılma','en':'Hug','de':'Umarmung','es':'Abrazo','fr':'Câlin'});
  String get kiss => _t({'tr':'Öpücük','en':'Kiss','de':'Kuss','es':'Beso','fr':'Bisou'});
  String get nudge => _t({'tr':'Dürtme','en':'Nudge','de':'Anstupsen','es':'Toque','fr':'Petit signe'});
  String get missYou => _t({'tr':'Seni özledim','en':'Miss you','de':'Ich vermisse dich','es':'Te extraño','fr':'Tu me manques'});
  String get forever => _t({'tr':'Sonsuza kadar','en':'Forever','de':'Für immer','es':'Para siempre','fr':'Pour toujours'});
  String get preparingCall => _t({'tr':'Hazırlanıyor…','en':'Preparing…','de':'Wird vorbereitet…','es':'Preparando…','fr':'Préparation…'});
  String get connectingCall => _t({'tr':'Bağlanıyor…','en':'Connecting…','de':'Verbindung wird hergestellt…','es':'Conectando…','fr':'Connexion…'});
  String get connectedCall => _t({'tr':'Bağlandı','en':'Connected','de':'Verbunden','es':'Conectado','fr':'Connecté'});
  String get connectionLost => _t({'tr':'Bağlantı koptu','en':'Connection lost','de':'Verbindung verloren','es':'Conexión perdida','fr':'Connexion perdue'});
  String get connectionFailed => _t({'tr':'Bağlantı başarısız','en':'Connection failed','de':'Verbindung fehlgeschlagen','es':'Error de conexión','fr':'Échec de la connexion'});
  String get callClosed => _t({'tr':'Arama kapandı','en':'Call closed','de':'Anruf beendet','es':'Llamada cerrada','fr':'Appel terminé'});
  String get voiceCall => _t({'tr':'Sesli arama','en':'Voice call','de':'Sprachanruf','es':'Llamada de voz','fr':'Appel vocal'});
  String get cameraOpenFailed => _t({'tr':'Kamera açılamadı','en':'Could not open camera','de':'Kamera konnte nicht geöffnet werden','es':'No se pudo abrir la cámara','fr':'Impossible d’ouvrir la caméra'});
  String get cameraSwitchFailed => _t({'tr':'Kamera değiştirilemedi','en':'Could not switch camera','de':'Kamera konnte nicht gewechselt werden','es':'No se pudo cambiar la cámara','fr':'Impossible de changer de caméra'});
  String get screenShareDenied => _t({'tr':'Ekran paylaşımı izni verilmedi.','en':'Screen sharing permission was denied.','de':'Die Berechtigung zur Bildschirmfreigabe wurde verweigert.','es':'Se denegó el permiso para compartir pantalla.','fr':'L’autorisation de partage d’écran a été refusée.'});
  String get screenShareStartFailed => _t({'tr':'Ekran paylaşımı başlatılamadı.','en':'Could not start screen sharing.','de':'Bildschirmfreigabe konnte nicht gestartet werden.','es':'No se pudo iniciar la pantalla compartida.','fr':'Impossible de démarrer le partage d’écran.'});
  String get screenShareActiveRemote => _t({'tr':'Partnerin ekranını paylaşıyor','en':'Your partner is sharing the screen','de':'Dein Partner teilt den Bildschirm','es':'Tu pareja está compartiendo la pantalla','fr':'Votre partenaire partage son écran'});
  String get screenShareActiveLocal => _t({'tr':'Ekranını paylaşıyorsun','en':'You are sharing your screen','de':'Du teilst deinen Bildschirm','es':'Estás compartiendo tu pantalla','fr':'Vous partagez votre écran'});

  String get startUsingTogether => _t({'tr':'Bestie alanını birlikte kullanmaya başlayın','en':'Start using Bestie together','de':'Startet gemeinsam mit Bestie','es':'Empiecen a usar Bestie juntos','fr':'Commencez à utiliser Bestie ensemble'});
  String get incomingLoveLetter => _t({'tr':'Partnerin sana bir mektup gönderdi.','en':'Your partner sent you a letter.','de':'Dein Partner hat dir einen Brief geschickt.','es':'Tu pareja te envió una carta.','fr':'Votre partenaire vous a envoyé une lettre.'});
  String get interactionLoadFailed => _t({'tr':'Etkileşim geçmişi yüklenemedi','en':'Could not load interaction history','de':'Interaktionsverlauf konnte nicht geladen werden','es':'No se pudo cargar el historial de interacciones','fr':'Impossible de charger l’historique des interactions'});

  String get sessionNotFound => _t({'tr':'Oturum bulunamadı','en':'Session not found','de':'Sitzung nicht gefunden','es':'Sesión no encontrada','fr':'Session introuvable'});
  String get callHistoryLoadFailed => _t({'tr':'Arama geçmişi yüklenemedi.','en':'Could not load call history.','de':'Anrufverlauf konnte nicht geladen werden.','es':'No se pudo cargar el historial de llamadas.','fr':'Impossible de charger l’historique des appels.'});
  String get noCallHistory => _t({'tr':'Henüz arama geçmişi yok.','en':'No call history yet.','de':'Noch kein Anrufverlauf.','es':'Aún no hay historial de llamadas.','fr':'Aucun historique d’appels pour le moment.'});
  String get outgoingCall => _t({'tr':'Giden arama','en':'Outgoing call','de':'Ausgehender Anruf','es':'Llamada saliente','fr':'Appel sortant'});
  String get incomingCallHistory => _t({'tr':'Gelen arama','en':'Incoming call','de':'Eingehender Anruf','es':'Llamada entrante','fr':'Appel entrant'});
  String get rejectedCall => _t({'tr':'Reddedildi','en':'Rejected','de':'Abgelehnt','es':'Rechazada','fr':'Refusé'});
  String get endedCall => _t({'tr':'Sonlandı','en':'Ended','de':'Beendet','es':'Finalizada','fr':'Terminé'});
  String get minutesShort => _t({'tr':'dk','en':'min','de':'Min.','es':'min','fr':'min'});

  String get hallOfFame => _t({'tr':'Şeref Köşesi','en':'Hall of Fame','de':'Ruhmeshalle','es':'Salón de la Fama','fr':'Mur des souvenirs'});
  String get hallOfFameSubtitle => _t({'tr':'Partnerinin en iyi ve en komik fotoğraflarını seç','en':'Curate your partner’s best and funniest photos','de':'Kuratiere die besten und lustigsten Fotos deines Partners','es':'Elige las fotos más bonitas y divertidas de tu pareja','fr':'Sélectionnez les photos les plus belles et drôles de votre partenaire'});
  String get hallOfFameAdd => _t({'tr':'Galeriden fotoğraf ekle','en':'Add photo from gallery','de':'Foto aus Galerie hinzufügen','es':'Añadir foto de la galería','fr':'Ajouter une photo depuis la galerie'});
  String get hallOfFameLimit => _t({'tr':'En fazla 10 fotoğraf ekleyebilirsin.','en':'You can add up to 10 photos.','de':'Du kannst bis zu 10 Fotos hinzufügen.','es':'Puedes añadir hasta 10 fotos.','fr':'Vous pouvez ajouter jusqu’à 10 photos.'});
  String get hallOfFameAura => _t({'tr':'Aura / Çekici','en':'Aura / Stunning','de':'Aura / Wow','es':'Aura / Increíble','fr':'Aura / Sublime'});
  String get hallOfFameMeme => _t({'tr':'Meme / İfşa','en':'Meme / Exposed','de':'Meme / Erwischt','es':'Meme / Pillado','fr':'Mème / Pris sur le fait'});
  String get hallOfFameMood => _t({'tr':'Tatlı / Mood','en':'Cute / Mood','de':'Süß / Mood','es':'Tendermoment / Mood','fr':'Mignon / Mood'});
  String get hallOfFameEmpty => _t({'tr':'Henüz bu köşede fotoğraf yok.','en':'No photos in this corner yet.','de':'Noch keine Fotos in dieser Ecke.','es':'Aún no hay fotos en esta sección.','fr':'Aucune photo dans cette section pour le moment.'});
  String get hallOfFameUploadFailed => _t({'tr':'Fotoğraf yüklenemedi.','en':'Could not upload the photo.','de':'Foto konnte nicht hochgeladen werden.','es':'No se pudo subir la foto.','fr':'Impossible de téléverser la photo.'});
  String get hallOfFameDelete => _t({'tr':'Fotoğrafı kaldır','en':'Remove photo','de':'Foto entfernen','es':'Supprimer la photo','fr':'Supprimer la photo'});
  String get hallOfFameDeleteFailed => _t({'tr':'Fotoğraf kaldırılamadı.','en':'Could not remove the photo.','de':'Foto konnte nicht entfernt werden.','es':'No se pudo eliminar la foto.','fr':'Impossible de supprimer la photo.'});
  String get hallOfFamePhotoNote => _t({'tr':'Fotoğraf notu','en':'Photo note','de':'Fotonotiz','es':'Nota de foto','fr':'Note sur la photo'});
  String get hallOfFameAddNote => _t({'tr':'Bir not ekle','en':'Add a note','de':'Notiz hinzufügen','es':'Añadir una nota','fr':'Ajouter une note'});
  String get hallOfFameSaved => _t({'tr':'Fotoğraf kaydedildi.','en':'Photo saved.','de':'Foto gespeichert.','es':'Foto guardada.','fr':'Photo enregistrée.'});

}
