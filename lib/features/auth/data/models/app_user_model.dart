import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/app_user.dart';

class AppUserModel extends AppUser {
  const AppUserModel({
    required super.id,
    required super.email,
    super.fullName,
  });

  factory AppUserModel.fromUser(User user) {
    return AppUserModel(
      id: user.id,
      email: user.email ?? '',
      fullName: user.userMetadata?['full_name'] as String?,
    );
  }
}
