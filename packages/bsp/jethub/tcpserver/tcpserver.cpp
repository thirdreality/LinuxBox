/*
 * Tcp server for wifi config.
 * Copyright (c) 3Reality 2023
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation
 * files (the "Software"), to deal in the Software without
 * restriction, including without limitation the rights to use,
 * copy, modify, merge, publish, distribute, sublicense, and/or
 * sell copies of the Software.
 *
*/
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/reboot.h>
#include <string.h>
#include <ctype.h>

#include "crypto_helper.h"

char host_name[20];
int port = 8090;

int main()
{
    struct sockaddr_in sin,pin;
    int sock_descriptor,temp_sock_descriptor;
    socklen_t address_size;
    int i , len , on=1;
    char recv_buf[128] = {0};
    char send_buf[32]="MAC:";
    char ssid[64] = {0}, pw[64] = {0}, thingname[64] = {0};
    char wifiAccount[64] = {0};

    sock_descriptor = socket(AF_INET,SOCK_STREAM,0);
    bzero(&sin,sizeof(sin));
    sin.sin_family = AF_INET;
    sin.sin_addr.s_addr = INADDR_ANY;
    sin.sin_port = htons(port);
    if(bind(sock_descriptor,(struct sockaddr *)&sin,sizeof(sin)) == -1)
    {
        printf("call to bind");
        goto exit;
    }
    if(listen(sock_descriptor,100) == -1)
    {
        printf("call to listem");
        goto exit;
    }
    printf("Accpting connections...\n");

    address_size = sizeof(pin);
    temp_sock_descriptor = accept(sock_descriptor,(struct sockaddr *)&pin,&address_size);
    if(temp_sock_descriptor == -1)
    {
        printf("call to accept");
        goto exit;
    }

    while(1)
    {
        if(recv(temp_sock_descriptor,recv_buf,128,0) == -1)
        {
            printf("call to recv");
            goto exit;
        }
        
        bool hasUser = false;
        if (strstr(recv_buf, "wifiAccount")) {
            hasUser = true;
        }
        if (strstr(recv_buf,"ssid"))
        {
            char *buf = strtok(recv_buf,"\n");
            strcpy(ssid, buf + strlen("ssid:"));
            printf("ssid = %s\n",ssid);

            buf = strtok(NULL,"\n");
            strcpy(pw, buf + strlen("pw:"));
            printf("pw = %s\n",pw);
            if (strlen(pw) > 0) {
                // decrypt the encrypted password
                char b64_message[128];
                sprintf(b64_message, "%s\n", pw);
                char* plain_pw = (char* )aes128_cbc_decrypt_base64(b64_message);
                strcpy(pw, plain_pw);
                free(plain_pw);
            }

            buf = strtok(NULL,"\n");
            strcpy(thingname, buf + strlen("thingname:"));
            printf("thingname = %s\n",thingname);
	    if (hasUser) {
	        buf = strtok(NULL,"\n");
                strcpy(wifiAccount, buf + strlen("wifiAccount:"));
                printf("-----------------------wifiAccount------------------ = %s\n",wifiAccount);
	    }
	   
            FILE *fp1 = fopen("/etc/ap_name","r");
            if (fread(send_buf+4, 1,12,fp1) < 1) {
                fclose(fp1);
                return -1;
            }
            fclose(fp1);

            for(i=0;i<16;i++)
            {
                send_buf[i]=toupper(send_buf[i]);
            }
            send(temp_sock_descriptor,send_buf,strlen(send_buf)+1,0);  //send \0 for Android APP
            printf("\n\n\nsend_buf=%s\n\n\n",send_buf);
#if 0
            FILE *fp2 = fopen("/data/user_thingname","w");
            if(fp2 !=NULL){
                fprintf(fp2,"%s\n",thingname);
                fclose(fp2);
            }
#endif
            FILE *fp = fopen("/etc/wpa_supplicant/wpa_supplicant-nl80211-wlan0.conf","w");
            if(fp !=NULL){
                if (strlen(wifiAccount) > 0 ) {
                    fprintf(fp,"network={\n\tssid=\"%s\"\n\tkey_mgmt=WPA-EAP IEEE8021X\n\teap=PEAP\n\tidentity=\"%s\"\n\tpassword=\"%s\"\n\tphase2=\"auth=MSCHAPV2\"\n\tpriority=78\n}\n",ssid,wifiAccount,pw);
                } else {
                    if (strlen(pw) > 0) {
                        if (strlen(pw) > 63) {
                            fprintf(fp,"network={\n\tssid=\"%s\"\n\tpsk=%s\n}\n",ssid,pw);
                        } else {
                            fprintf(fp,"network={\n\tssid=\"%s\"\n\tpsk=\"%s\"\n}\n",ssid,pw);
                        }
                    } else { // no password, open wifi
                        fprintf(fp, "network={\n\tssid=\"%s\"\n\tkey_mgmt=NONE\n}\n", ssid);
                    }
                }
                fclose(fp);
            }
#if 0
            // touch "/etc/wifi/wifi_station"
            fp = fopen("/etc/wifi/wifi_station", "w");
            if(fp !=NULL){
                fclose(fp);
            }

            FILE *fp3 = fopen("/data/ssid","w");
            if(fp3 != NULL){
                fprintf(fp3,"%s",ssid);
                fclose(fp3);
            }
#endif
            memset(recv_buf,0,128);
            usleep(100*1000);
        }

        if (strstr(recv_buf, "OK"))
        {
            printf("\nReceived OK from APP!\n");
            // FILE *wifi_info = fopen("/var/www/cgi-bin/wifi/select.txt", "w");
            //  printf("%s\n%s\n", ssid, pw);
            // fclose(wifi_info);

            // starting to setup the WIFI network
            // system("/var/www/cgi-bin/wifi/wifi_tool.sh");
            system("/sbin/reboot");

            goto exit;
        }
    }
exit:
    if(sock_descriptor){
	close(sock_descriptor);
    }
    if(temp_sock_descriptor){
	close(temp_sock_descriptor);
    }
    return 0;
}
