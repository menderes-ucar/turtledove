import 'package:supabase_flutter/supabase_flutter.dart';

/// Resolves notification copy in the recipient's preferred app language.
///
/// User-generated content (message text, letter text, place names, task names,
/// etc.) is intentionally never translated. Only Bestie-owned notification
/// copy is localized here.
class NotificationLocalizer {
  static const supported = {'tr', 'en', 'de', 'es', 'fr'};

  static String normalize(String? code) {
    final value = (code ?? '').trim().toLowerCase();
    return supported.contains(value) ? value : 'en';
  }

  static Map<String, String> localize({
    required String language,
    required String type,
    required String title,
    required String body,
    Map<String, dynamic> data = const {},
  }) {
    final l = normalize(language);
    final action = data['action']?.toString() ?? '';
    final interactionType = data['interaction_type']?.toString() ?? '';
    final gameType = data['game_type']?.toString() ?? '';

    String t(String tr, String en, String de, String es, String fr) {
      switch (l) {
        case 'tr': return tr;
        case 'de': return de;
        case 'es': return es;
        case 'fr': return fr;
        default: return en;
      }
    }

    var localizedTitle = title;
    var localizedBody = body;

    switch (type) {
      case 'pairing':
        if (action == 'paired') {
          localizedTitle = t(
            'Eşleşme tamamlandı 💕',
            'Pairing completed 💕',
            'Verbindung hergestellt 💕',
            'Emparejamiento completado 💕',
            'Jumelage terminé 💕',
          );
          final name = data['partner_name']?.toString();
          localizedBody = name != null && name.isNotEmpty
              ? t('$name seninle eşleşti.', '$name paired with you.', '$name hat sich mit dir verbunden.', '$name se ha emparejado contigo.', '$name s’est jumelé avec toi.')
              : t('Seninle eşleşti.', 'Paired with you.', 'Hat sich mit dir verbunden.', 'Se ha emparejado contigo.', 'S’est jumelé avec toi.');
        } else if (action == 'unpaired') {
          localizedTitle = t(
            'Eşleşme sona erdi 💔',
            'Pairing ended 💔',
            'Verbindung beendet 💔',
            'El emparejamiento terminó 💔',
            'Le jumelage est terminé 💔',
          );
          final name = data['partner_name']?.toString();
          localizedBody = name != null && name.isNotEmpty
              ? t('$name eşleşmeyi bitirdi.', '$name ended the pairing.', '$name hat die Verbindung beendet.', '$name terminó el emparejamiento.', '$name a mis fin au jumelage.')
              : t('Eşleşme sona erdi.', 'The pairing has ended.', 'Die Verbindung wurde beendet.', 'El emparejamiento ha terminado.', 'Le jumelage est terminé.');
        }
        break;

      case 'message':
        localizedTitle = t('Yeni mesaj', 'New message', 'Neue Nachricht', 'Nuevo mensaje', 'Nouveau message');
        if (action == 'media') {
          localizedBody = t('Yeni bir medya mesajı gönderildi.', 'A new media message was sent.', 'Eine neue Mediennachricht wurde gesendet.', 'Se envió un nuevo mensaje multimedia.', 'Un nouveau message multimédia a été envoyé.');
        }
        break;

      case 'love_letter':
        localizedTitle = t('Yeni mektup 💌', 'New letter 💌', 'Neuer Brief 💌', 'Nueva carta 💌', 'Nouvelle lettre 💌');
        break;

      case 'interaction':
        localizedTitle = _interactionTitle(
          t, interactionType, title,
        );
        localizedBody = t(
          'Partnerinden yeni bir etkileşim geldi.',
          'You received a new interaction from your partner.',
          'Du hast eine neue Interaktion von deinem Partner erhalten.',
          'Recibiste una nueva interacción de tu pareja.',
          'Tu as reçu une nouvelle interaction de ton/ta partenaire.',
        );
        break;

      case 'map':
        if (action == 'country_added') {
          localizedTitle = t('Yeni ülke seçildi 📍', 'New country selected 📍', 'Neues Land ausgewählt 📍', 'Nuevo país seleccionado 📍', 'Nouveau pays sélectionné 📍');
        } else if (action == 'city_added') {
          localizedTitle = t('Yeni şehir seçildi 📍', 'New city selected 📍', 'Neue Stadt ausgewählt 📍', 'Nueva ciudad seleccionada 📍', 'Nouvelle ville sélectionnée 📍');
        }
        break;

      case 'place':
        localizedTitle = t('Yeni yer kaydedildi', 'New place saved', 'Neuer Ort gespeichert', 'Nuevo lugar guardado', 'Nouveau lieu enregistré');
        break;

      case 'todo':
        if (action == 'completed') {
          localizedTitle = t('Görev tamamlandı ✅', 'Task completed ✅', 'Aufgabe erledigt ✅', 'Tarea completada ✅', 'Tâche terminée ✅');
        } else if (action == 'reopened') {
          localizedTitle = t('Görev yeniden açıldı', 'Task reopened', 'Aufgabe wieder geöffnet', 'Tarea reabierta', 'Tâche rouverte');
        } else {
          localizedTitle = t('Yeni görev', 'New task', 'Neue Aufgabe', 'Nueva tarea', 'Nouvelle tâche');
        }
        break;

      case 'mood':
        localizedTitle = t('Partnerinin ruh hali güncellendi', 'Your partner updated their mood', 'Dein Partner hat seine Stimmung aktualisiert', 'Tu pareja actualizó su estado de ánimo', 'Ton/ta partenaire a mis à jour son humeur');
        localizedBody = t('Partnerin yeni bir ruh hali paylaştı.', 'Your partner shared a new mood.', 'Dein Partner hat eine neue Stimmung geteilt.', 'Tu pareja compartió un nuevo estado de ánimo.', 'Ton/ta partenaire a partagé une nouvelle humeur.');
        break;

      case 'countdown':
        localizedTitle = t('Yeni geri sayım', 'New countdown', 'Neuer Countdown', 'Nueva cuenta atrás', 'Nouveau compte à rebours');
        break;

      case 'pet':
        if (action == 'created') {
          localizedTitle = t('Yeni ortak evcil hayvan', 'New shared pet', 'Neues gemeinsames Haustier', 'Nueva mascota compartida', 'Nouvel animal partagé');
          final name = data['pet_name']?.toString();
          localizedBody = name != null && name.isNotEmpty
              ? t(
                  '$name artık sizin ortak evcil hayvanınız.',
                  '$name is now your shared pet.',
                  '$name ist jetzt euer gemeinsames Haustier.',
                  '$name ahora es vuestra mascota compartida.',
                  '$name est maintenant votre animal partagé.',
                )
              : t(
                  'Yeni bir ortak evcil hayvanınız var.',
                  'You have a new shared pet.',
                  'Ihr habt ein neues gemeinsames Haustier.',
                  'Tenéis una nueva mascota compartida.',
                  'Vous avez un nouvel animal partagé.',
                );
        } else {
          localizedTitle = t('Pet aktivitesi', 'Pet activity', 'Haustier-Aktivität', 'Actividad de mascota', 'Activité de l’animal');
          final actionName = data['action_name']?.toString() ?? data['action']?.toString();
          if (actionName != null && actionName.isNotEmpty) {
            localizedBody = t(
              'Ortak evcil hayvanınız için bir aktivite yapıldı.',
              'An activity was completed for your shared pet.',
              'Eine Aktivität für euer gemeinsames Haustier wurde ausgeführt.',
              'Se realizó una actividad para vuestra mascota compartida.',
              'Une activité a été réalisée pour votre animal partagé.',
            );
          }
        }
        break;

      case 'call':
        localizedBody = t('Gelen arama 📞', 'Incoming call 📞', 'Eingehender Anruf 📞', 'Llamada entrante 📞', 'Appel entrant 📞');
        break;

      case 'call_end':
        localizedTitle = t('Arama sona erdi', 'Call ended', 'Anruf beendet', 'Llamada finalizada', 'Appel terminé');
        localizedBody = t('Turtle Dove araması sona erdi.', 'The Turtle Dove call has ended.', 'Der Turtle Dove-Anruf wurde beendet.', 'La llamada de Turtle Dove ha terminado.', 'L’appel Turtle Dove est terminé.');
        break;

      case 'game':
        final game = _gameLabel(t, gameType);
        if (action == 'player_ready') {
          localizedTitle = t('Oyuncu hazır 🎮', 'Player ready 🎮', 'Spieler bereit 🎮', 'Jugador listo 🎮', 'Joueur prêt 🎮');
          localizedBody = t('Partnerin oyuna hazır. Sen de hazırsan başlayabilirsiniz.', 'Your partner is ready. Start when you are.', 'Dein Partner ist bereit. Startet, wenn du auch bereit bist.', 'Tu pareja está lista. Empiecen cuando tú también lo estés.', 'Ton/ta partenaire est prêt(e). Commencez quand tu le seras aussi.');
        } else if (action == 'answer_submitted') {
          localizedTitle = t('Oyunda sıra sende 🎮', 'Your turn 🎮', 'Du bist dran 🎮', 'Es tu turno 🎮', 'À toi de jouer 🎮');
          localizedBody = t('Partnerin bu turu cevapladı. Senin cevabını bekliyor.', 'Your partner answered this round and is waiting for you.', 'Dein Partner hat diese Runde beantwortet und wartet auf dich.', 'Tu pareja respondió esta ronda y te espera.', 'Ton/ta partenaire a répondu à cette manche et attend ta réponse.');
        } else if (action == 'surrendered') {
          localizedTitle = t('Oyun sona erdi 🏆', 'Game ended 🏆', 'Spiel beendet 🏆', 'Juego terminado 🏆', 'Partie terminée 🏆');
          localizedBody = t('Partnerin oyundan çıktı.', 'Your partner left the game.', 'Dein Partner hat das Spiel verlassen.', 'Tu pareja salió del juego.', 'Ton/ta partenaire a quitté la partie.');
        } else if (action == 'turn_changed') {
          localizedTitle = t('Sıra sende 🔤', 'Your turn 🔤', 'Du bist dran 🔤', 'Es tu turno 🔤', 'À toi de jouer 🔤');
        } else if (action == 'round_confirmed') {
          localizedTitle = t('Tur onaylandı 🎮', 'Round confirmed 🎮', 'Runde bestätigt 🎮', 'Ronda confirmada 🎮', 'Manche confirmée 🎮');
          localizedBody = t('Partnerin turu onayladı. Sen de onaylarsan sonraki tur başlayacak.', 'Your partner confirmed the round. Confirm too to start the next round.', 'Dein Partner hat die Runde bestätigt. Bestätige ebenfalls für die nächste Runde.', 'Tu pareja confirmó la ronda. Confirma también para comenzar la siguiente.', 'Ton/ta partenaire a confirmé la manche. Confirmez aussi pour commencer la suivante.');
        } else if (action == 'review_ready') {
          localizedTitle = t('Cevapları kontrol et 🎯', 'Review the answers 🎯', 'Antworten prüfen 🎯', 'Revisa las respuestas 🎯', 'Vérifie les réponses 🎯');
          localizedBody = t('Süre bitti. Partnerinin cevaplarını kontrol et.', 'Time is up. Review your partner’s answers.', 'Die Zeit ist abgelaufen. Prüfe die Antworten deines Partners.', 'Se acabó el tiempo. Revisa las respuestas de tu pareja.', 'Le temps est écoulé. Vérifie les réponses de ton/ta partenaire.');
        } else if (action == 'review_submitted') {
          localizedTitle = t('Cevaplar kontrol edildi ✓', 'Answers reviewed ✓', 'Antworten geprüft ✓', 'Respuestas revisadas ✓', 'Réponses vérifiées ✓');
          localizedBody = t('Partnerin cevaplarını kontrol etti.', 'Your partner reviewed the answers.', 'Dein Partner hat die Antworten geprüft.', 'Tu pareja revisó las respuestas.', 'Ton/ta partenaire a vérifié les réponses.');
        } else if (action == 'round_started') {
          localizedTitle = t('Yeni tur başladı 🎯', 'New round started 🎯', 'Neue Runde gestartet 🎯', 'Nueva ronda iniciada 🎯', 'Nouvelle manche commencée 🎯');
          localizedBody = t('İsim Şehir Hayvan için yeni tur başladı.', 'A new Name City Animal round has started.', 'Eine neue Runde Name, Stadt, Tier hat begonnen.', 'Ha comenzado una nueva ronda de Nombre, ciudad y animal.', 'Une nouvelle manche de Prénom, ville, animal a commencé.');
        } else if (action == 'game_completed' || action == 'completed') {
          localizedTitle = game.isEmpty
              ? t('Oyun tamamlandı 🏆', 'Game completed 🏆', 'Spiel abgeschlossen 🏆', 'Juego completado 🏆', 'Partie terminée 🏆')
              : t('$game tamamlandı 🏆', '$game completed 🏆', '$game abgeschlossen 🏆', '$game completado 🏆', '$game terminé 🏆');
          localizedBody = t('Oyun tamamlandı.', 'The game is complete.', 'Das Spiel ist abgeschlossen.', 'El juego ha terminado.', 'La partie est terminée.');
        } else {
          localizedTitle = game.isEmpty
              ? t('Yeni oyun daveti', 'New game invitation', 'Neue Spieleinladung', 'Nueva invitación de juego', 'Nouvelle invitation de jeu')
              : t('$game daveti 🎮', '$game invitation 🎮', '$game-Einladung 🎮', 'Invitación a $game 🎮', 'Invitation à $game 🎮');
          localizedBody = t('Oyuna davet edildin.', 'You were invited to play.', 'Du wurdest zum Spielen eingeladen.', 'Te han invitado a jugar.', 'Tu as été invité(e) à jouer.');
        }
        break;

      default:
        // Keep unknown/user-generated notification copy intact rather than
        // guessing or corrupting content.
        break;
    }

    return {'title': localizedTitle, 'body': localizedBody};
  }

  static String _interactionTitle(
    String Function(String, String, String, String, String) t,
    String type,
    String fallback,
  ) {
    switch (type) {
      case 'hug':
        return t('Sarılma', 'Hug', 'Umarmung', 'Abrazo', 'Câlin');
      case 'kiss':
        return t('Öpücük', 'Kiss', 'Kuss', 'Beso', 'Bisou');
      case 'nudge':
        return t('Dürtme', 'Nudge', 'Anstupsen', 'Toque', 'Petit signe');
      case 'miss_you':
        return t('Seni özledim', 'Miss you', 'Ich vermisse dich', 'Te extraño', 'Tu me manques');
      case 'infinity':
        return t('Sonsuza kadar', 'Forever', 'Für immer', 'Para siempre', 'Pour toujours');
      default:
        return fallback;
    }
  }

  static String _gameLabel(
    String Function(String, String, String, String, String) t,
    String gameType,
  ) {
    switch (gameType) {
      case 'trivia':
        return t('Bilgi Yarışması', 'Trivia', 'Quiz', 'Trivia', 'Quiz');
      case 'most_likely_to':
        return t('En Çok Kim?', 'Most Likely To', 'Wer würde eher?', 'Quién es más probable', 'Qui est le plus susceptible');
      case 'word_game':
        return t('Kelime Oyunu', 'Word Game', 'Wortspiel', 'Juego de palabras', 'Jeu de mots');
      case 'memory_match':
        return t('Hafıza Oyunu', 'Memory Match', 'Memory Match', 'Memory Match', 'Memory Match');
      case 'truth_or_dare':
        return t('Doğruluk mu Cesaret mi?', 'Truth or Dare', 'Wahrheit oder Pflicht', 'Verdad o reto', 'Action ou vérité');
      case 'name_city_animal':
        return t('İsim Şehir Hayvan', 'Name City Animal', 'Name Stadt Tier', 'Nombre Ciudad Animal', 'Prénom Ville Animal');
      default:
        return '';
    }
  }
}
