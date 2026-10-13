import 'package:flutter/material.dart';
import '../../localization/app_strings.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/notification_service.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});
  @override Widget build(BuildContext context) {
    final uid=Supabase.instance.client.auth.currentUser?.id;
    if(uid==null) return Scaffold(body:Center(child:Text(AppStrings.of(context).sessionNotFound)));
    final service=context.read<NotificationService>();
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.of(context).notifications),
        actions:[TextButton(onPressed:()=>service.markAllRead(uid), child:Text(AppStrings.of(context).markAllRead))],
      ),
      body:StreamBuilder<List<AppNotification>>(
        stream:service.stream(uid),
        builder:(context,snap){
          if(snap.hasError)return Center(child:Text(AppStrings.of(context).notificationsLoadFailed));
          if(!snap.hasData)return const Center(child:CircularProgressIndicator());
          final items=snap.data!;
          if(items.isEmpty)return Center(child:Text(AppStrings.of(context).noNotifications));
          return ListView.separated(
            padding:const EdgeInsets.all(16), itemCount:items.length, separatorBuilder:(_,__)=>const SizedBox(height:10),
            itemBuilder:(_,i){final n=items[i]; return Card(
              child:ListTile(
                leading:CircleAvatar(child:Icon(_icon(n.type))),
                title:Text(n.title,style:TextStyle(fontWeight:n.isRead?FontWeight.normal:FontWeight.w800)),
                subtitle:Text(n.body),
                trailing:n.isRead?null:const Icon(Icons.circle,size:10),
                onTap:()=>service.markRead(n.id),
              ),
            );}
          );
        }
      )
    );
  }
  IconData _icon(String type)=>switch(type){'message'=>Icons.chat_bubble_outline,'interaction'=>Icons.favorite,'call'=>Icons.call,'pet'=>Icons.pets,'game'=>Icons.games,'special'=>Icons.auto_awesome,_=>Icons.notifications_none};
}
