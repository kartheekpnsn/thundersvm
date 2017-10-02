//
// Created by jiashuai on 17-9-17.
//
#include "gtest/gtest.h"
#include "thundersvm/syncdata.h"
TEST(SyncDataTest, host_allocate){
    SyncData<int> syncData(100);
    EXPECT_NE(syncData.host_data(), nullptr);
    EXPECT_EQ(syncData.head(), SyncMem::HEAD::HOST);
    EXPECT_EQ(syncData.size(), sizeof(int) * 100);
    EXPECT_EQ(syncData.count(), 100);
    syncData.resize(20);
    EXPECT_EQ(syncData.head(), SyncMem::UNINITIALIZED);
    EXPECT_EQ(syncData.count(), 20);
}

TEST(SyncDataTest, device_allocate){
    SyncData<int> syncData(100);
    EXPECT_NE(syncData.device_data(), nullptr);
    EXPECT_EQ(syncData.head(), SyncMem::HEAD::DEVICE);
    EXPECT_EQ(syncData.size(), sizeof(int) * 100);
    EXPECT_EQ(syncData.count(), 100);
    syncData.resize(20);
    EXPECT_EQ(syncData.head(), SyncMem::UNINITIALIZED);
    EXPECT_EQ(syncData.count(), 20);
}

TEST(SyncDataTest, host_to_device){
    SyncData<int> syncData(10);
    int *data = syncData.host_data();
    for (int i = 0; i < 10; ++i) {
        data[i] = i;
    }
    syncData.to_device();
    EXPECT_EQ(syncData.head(), SyncMem::HEAD::DEVICE);
    for (int i = 0; i < 10; ++i) {
        data[i] = -1;
    }
    syncData.to_host();
    EXPECT_EQ(syncData.head(), SyncMem::HEAD::HOST);
    data = syncData.host_data();
    for (int i = 0; i < 10; ++i) {
        EXPECT_EQ(data[i] , i);
    }
    for (int i = 0; i < 10; ++i) {
        EXPECT_EQ(syncData[i] , i);
    }
}