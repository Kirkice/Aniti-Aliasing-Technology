# HiZ Cull

**HiZ 遮挡剔除工具**


![image (5)](Images/HiZOn.jpeg)

***

# 比较
开启HiZ 截图
![image (5)](Images/HiZOn.jpeg)

关闭HiZ 截图
![image (5)](Images/HiZOff.jpeg)

# 使用说明
- 1.将压缩包解压并导入到package目录进行安装

- 2.找到UniversalRendererData,将HiZRenderFeature添加上去，并设置feature的Compute Shader：Cull Shader -> HizCullMask, Generate MipMap->GenerateMipMap

- 3.打开需要剔除的场景，在Hierachy面板上右键->Rendering->Occlusion Cull->HiZ Cull创建HiZCtrl组件,给RendererData拖入找到UniversalRendererData

- 4.给需要被遮挡的预设添加上HiZCull Item组件

- 5.点击HiZCtrl面板，调整长宽以适应包含所有的HiZCullItme，点击【收集被遮挡物】按钮，可以看到下方的List里包含了所有的HiZCullItem

- 6.运行时点击【开启HiZ】/ 【关闭HiZ】按钮即可启用或关闭。（代码调用 OnEnableHiZ() / OnDisableHiZ() 方法） 

***
## 【HizCull Ctrl】面板

![image (5)](Images/01.png)

## 测试场景

![image (5)](Images/02.png)

## Hiz Cull Item 显示自己的AABB

![image (5)](Images/03.png)

