import os

from libc.stdlib cimport malloc,free,realloc

from libc.stdio cimport fopen, fwrite, fread,fclose,FILE 

from parser.Init_Thes import Init_thesaurus , init_hashIndex


import sqlite3 as sq



DEF STEP=20



#定义 hashIndex 结构
cdef struct HI: #hashIndex 结构
    int left    #左侧范围
    int right   #右侧范围
    

DEF List_init_size = 100  #定义List初始化长度

DEF List_num = 20         #hit_lists中划分 块 数目

DEF Doc_Each_Contain = 100  #每个文件中的占有的文件数目


#定义 Hit 结构
cdef struct Hit:
    int wordID
    int docID
    short score
    int pos


#单个list结构
cdef struct List:
    Hit *start
    int length
    int top
    int size        #此记录中的总hit数目  初始化时需要使用


cdef class Hit_lists:

    '''
    hit存储队列
    每个list对应于一个存储文件
    '''

    cdef:
        int length
        int top
        List hit_list[List_num]

    def __cinit__(self):

        '''
        初始化数据空间
        '''

        print '>begin init List space'

        cdef:
            int i

        #初始化每个list节点
        for i in range(List_num):

            self.hit_list[i].start=<Hit *>malloc( sizeof(Hit) * List_init_size )
            self.hit_list[i].length=List_init_size
            self.hit_list[i].top=-1
            self.hit_list[i].size=0

            if self.hit_list[i].start!= NULL:

                print '>>init list ok!'


    cdef __delloc__(self):

        '''
        消去内存
        '''

        cdef int i

        print 'begin to delete the space'

        for i in range(List_num):
            free(self.hit_list[i].start)


    cdef void eq(self,int hit_id,int idx,int wordID,int docID,short score,int pos):

        '''
        赋值处理
        '''

        self.hit_list[hit_id].start[idx].wordID=wordID

        self.hit_list[hit_id].start[idx].docID=docID

        self.hit_list[hit_id].start[idx].score=score

        self.hit_list[hit_id].start[idx].pos=pos




    def ap(self,int hit_id , int wordID , int docID , short score , int pos):

        '''
        向list中添加数据
        如果list溢出 则返回False
        添加成功 返回True
        '''
        #print 'begin append the word hit >>>>>'

        self.hit_list[hit_id].top += 1
        self.hit_list[hit_id].size += 1

        print '+ hit.top+1'
        #print '+ begin eq'

        self.eq( hit_id, self.hit_list[hit_id].top ,wordID,docID,score,pos)

        #print '> succed eq'

        if (self.hit_list[hit_id].top > self.hit_list[hit_id].length-2):
            #如果 分配长度快到最大长度 则返回false
            #如果 lenth还有空间 继续分配空间

           return False

        else:
            #空间和其他都不缺少
            #正常情况
            return True


    cdef void empty(self,int hit_id):

        '''
        将List清空
        释放空间
        再重新分配基本空间
        '''

        print 'begin to free the list'
        print 'begin to relloc it'

        self.hit_list[hit_id].top=-1



cdef class Indexer:
######################################
#        开始仅仅使用wid
#
######################################
    '''
    索引器
    最终将要产生两类hit
    一类为 docID 排序
    一类为 wID 排序

    在 docID 排序的时候 
    在扫描 wID 同时 存储 docID

    docID 需要 根据 文件个数 确定 每快存储长度
    最终需要根据 wID进行排序
    wordID 需要根据 wordID 进行排序
    ???????????两者均需要排序????????????
    '''

    #文件目录地址
    cdef char *fph

    cdef char *toph

    cdef Hit_lists hit_list

    cdef object thes

    cdef object hash_index

    #数据库相关
    cdef object cx
    
    cdef object cu

    #词库
    def __cinit__(self,char *wph,char *fph,char *toph):

        '''
        init
        ph: wordsplit文件目录地址
        '''

        self.fph=fph
        self.toph=toph

        #初始化 Hit_list
        self.hit_list = Hit_lists()
        #词库
        self.thes = Init_thesaurus(wph)

        self.hash_index = init_hashIndex('store/index_hash.b','store/word_wide.txt')


        self.cx = sq.connect('store/chun.sqlite')

        self.cu = self.cx.cursor()


    cdef int loc_list(self,hashvalue):

        '''
        传入一个word
        定位 其 应该存在的 list 
        可以继承 词库 
        '''

        return self.hash_index.pos(hash(hashvalue))


    cdef void __save_hit_size(self,char *ph):

        '''
        保存每个hitlist的数量
        以便初始化
        '''
        print 'begin to save hit_size'
        
        cdef:
            int i

        strr=''

        for i in range(List_num):
           strr += str( self.hit_list.hit_list[i].size ) + ' '

        f=open(ph,'w')
        f.write(strr)
        f.close()


    def run(self):

        '''
        运行主程序
        需要同时对wordid 和 docid 进行分类保存

        '''

        cdef:
            int list_idx    #定位 list 的号码
            object li
            object c
            #词库长度
            int length
            #相对pos
            int abspos

        cdef:
            int pos
            #wordid 
            long wid
            int scoid
            #对应于 list 中 的 list_id
            int docid

        li=os.listdir(self.fph)

        length=len(li)
        
        dig = 0

        for doc in li:

            print 'doc is',doc

            f=open(self.fph+'/'+doc)
            c=f.read()
            f.close()

            tags=c.split('@chunwei@')
            abspos=0
            
            if scoid == 1:
                #开始添加des 索引
                self.add_des_index(self,docID)

            for scoid,tag in enumerate(tags):

                #对每个标签进行处理
                words = []

                ########################
                #
                #   开始添加 des
                #
                ########################

                if scoid == 1:
                    words += self.get_split_des_words(doc)

                words += tag.split()
                

                for pos,word in enumerate(words):

                    #开始扫面每一个tag ?????????????????????
                    print '开始在词库中查词'

                    wid=self.thes.find(word)
                    print 'from wordBar find',wid
                    #定位 list号码
                    list_idx=self.loc_list(word)

                    #若 wid 为 0 表示 词汇不存在

                    if wid != 0:
                        #此处 为了将不同tag内的hit的pos完全分给开
                        #采用 自动添加 20 作为间隔
                        
                        #print list_idx,wid,doc,scoid, pos+abspos+20

                        #print 'begin append'

                        if self.hit_list.ap(list_idx,wid,int(doc),scoid, pos+abspos+20 ) == 1:

                            pass

                        else:

                            #将 list_idx 对应的list写入到文件

                            print '-'*50
                            print 'the stack is full'

                            self.add_save(list_idx)



                            print 'begin to empty the stack'

                            #将相应list清空
                            self.hit_list.empty(list_idx)

        #将剩余的hits进行存储
        #一些list hit 数目不超过 max_size
        for i in range(List_num):
            self.add_save(i)
            

    cdef get_split_des_words(self,docID):
        
        '''
        添加 des 的 hash
        '''
        self.cu.execute("select split_des from lib where docID = %d"%docID)

        li= self.cu.fetchone()
        if li:
            print 'get des',li
            return li[0].split()
        else:
            return ['']



    cdef sort(self):

        '''
        将结果逐个进行排序
        在客户端已经进行排序???
        '''
        pass



    cdef void add_save(self,int list_idx):

        '''
        将相关内容添加到文件中 
        默认 便是 在 wordID 范围内乱序排列
        '''
        print '>> add save'
        print '-'*50

        name=self.toph+'/'+str(list_idx)+'.hit'
        
        print 'the docname is',name

        cdef char *fh=name

        cdef FILE *fp=<FILE *>fopen(fh,"ab")

        #此处 size 需要???????????????????????????????????????

        fwrite( self.hit_list.hit_list[list_idx].start , sizeof(Hit) ,  self.hit_list.hit_list[list_idx].top+1 , fp)
        fclose(fp)

        #保存 hit 记录数目
        self.__save_hit_size('store/hits/hit_size.txt')



##############################
#    hit 排序
##############################

#导入 hit_sort库
##################################################
#
#           hit_sort
#
##################################################
cdef class Sorter:

    '''
    排序主算法	
    '''

    cdef Hit *dali
    cdef int length
	
    #def __cinit__(self, Hit *data,int length):


    cdef void init(self,Hit *data,int length):

        '''
        init 
        '''

        self.dali=data
        self.length=length


    cdef double gvalue(self,Hit data):

        '''
		返回需要进行比较的值
        '''
        return data.wordID


    def quicksort(self,int p,int q):

        cdef int j

        a=self.dali

        st=[]

        while True:

            while p<q:

                j=self.partition(p,q)

                if (j-p)<(q-j):
                    st.append(j+1)
                    st.append(q)
                    q=j-1

                else:
                    st.append(p)
                    st.append(j-1)
                    p=j+1

            if(len(st)==0):
                return

            q=st.pop()
            p=st.pop()


    cdef int partition(self,int low,int high):
        cdef Hit v
        v=self.dali[low]

        while low<high:

            while low<high and self.gvalue( self.dali[high] ) >= self.gvalue( v ):
                high-=1
            self.dali[low]=self.dali[high]

            while low<high and self.gvalue( self.dali[low] )<=self.gvalue( v ):
                low+=1
            self.dali[high]=self.dali[low]

        self.dali[low]=v

        return low

#------------------------ Sorter end --------------------------------------


cdef class wid_sort(Sorter):

    '''
    根据 wid 进行排序
    不包括最后 根据 docid 进行排序
    '''

    #词库
    cdef object wordbar
	
    def __cinit__(self):

        '''
        init 
        '''
        pass

        #self.wordbar = Init_thesaurus('store/wordBar')


    cdef void init1(self,Hit *data,int length):

        '''
        初始化 父亲 Sorter
        '''

        Sorter.init(self,data,length)


    cdef double gvalue(self,Hit data):

        '''
        重载 Sorter 方法
		返回需要进行比较的值
        '''

        cdef int wid=data.wordID
        #返回 hit 对应 word 的 hashvalue
        #return hash( self.wordbar.wlist[wid] )
        return wid



cdef class did_sort(Sorter):

    '''
    根据 did 进行排序
    不包括 在 耽搁 did 文件中 根据 wid 进行排序
    '''

    def __cinit__(self):

        '''
        init
        '''

        pass


    cdef void init1(self,Hit *data,int length):

        '''
        初始化 父亲 Sorter
        '''

        Sorter.init(self,data,length)


    cdef double gvalue(self,Hit data):
        '''
        返回排序字段
        '''
        return data.docID
    

cdef class sco_sort(Sorter):

    '''
    根据 did 进行排序
    不包括 在 耽搁 did 文件中 根据 wid 进行排序
    '''

    def __cinit__(self):

        '''
        init
        '''

        pass


    cdef void init1(self,Hit *data,int length):

        '''
        初始化 父亲 Sorter
        '''

        Sorter.init(self,data,length)


    cdef double gvalue(self,Hit data):
        '''
        返回排序字段
        '''
        return data.score



cdef class hit_sort:

    '''
    使用 indexer 添加 hit 后
    使用 hit_sort 进行排序
    '''

    cdef Hit *hi
    #定义 wid 排序器
    cdef wid_sort widSorter
    #定义 did 排序起
    cdef did_sort didSorter
    #定义 sco 排序
    cdef sco_sort scoSorter


    def __cinit__(self):

        '''
        init
        '''

        self.widSorter = wid_sort()
        self.didSorter = did_sort()
        self.scoSorter = sco_sort()


    cdef void init(self,Hit *start,int length):
        '''
        struct 端的初始化程序
        '''
        #初始化
        self.widSorter.init1(start,length)
        self.scoSorter.init1(start,length)
        self.didSorter.init1(start,length)


    def sort_in_wid(self,int start,int end):

        '''
        根据wid进行排序
        '''
        self.widSorter.quicksort(start,end)


    def sort_in_did(self,int start,int end):
        
        '''
        根据did进行排序
        '''
        self.didSorter.quicksort(start,end)


    def sort_in_sco(self,int start,int end):
        
        '''
        根据sco进行排序
        '''
        self.scoSorter.quicksort(start,end)


    cdef save_b(self,char *ph,int num):

        '''
        二进制保存文件
        '''

        print 'begin to save b file'

        cdef FILE *fp=<FILE *>fopen(ph,"wb")
        fwrite(self.hi,sizeof(Hit),num,fp)
        fclose(fp)


    cdef int get_hit_num(docph):

        '''
        返回 每个 wid文件的hit 的数量
        '''

        pass





    


#################################################
#
#  **********   end of hit_sort ***************
#
#################################################

cdef class Sort_hits:

    '''
    对 hits 进行排序
    包括对 hits 的排序
    '''

    cdef Hit *hit_list

    cdef int length #hitlist的长度

    cdef int width[List_num]

    def __cinit__(self,char *width_ph):

        '''
        init
        '''

        #初始化width
        f = open(width_ph)
        c=f.read()
        f.close()

        cdef int i=0
        #初始化 每个文件的 hit 数量记录
        for w in c.split():
            self.width[i]=int(w) 
            i+=1

        #初始化 排序库 ????????????????

        print 'init ok!'


    def init(self,char *fdir,int index):

        '''
        从 hit 文件中初始化 hit_list
        分配内存
        '''

        if(self.hit_list != NULL):

            print 'the former hits is not empty'
            print 'free the former hit_list'
            free(self.hit_list)

        print 're malloc'
        self.hit_list= <Hit *> malloc ( sizeof(Hit) * self.width[index] )

        print 'begin read the file'

        ind=str(index) 

        fname = fdir +ind +'.hit'
        
        cdef char *fn = fname

        print 'the fname is',fn

        cdef FILE *fp=<FILE *>fopen(fn,"rb")

        fread(self.hit_list , sizeof(Hit), self.width[index] ,fp)

        fclose(fp)

        #初始化基础信息
        #负值hit_list长度
        self.length = self.width[index]


    def show(self):

        '''
        展示结果
        '''
        cdef:
            int i
        for i in range(self.length):
            print i,self.hit_list[i].wordID,self.hit_list[i].docID,self.hit_list[i].score,self.hit_list[i].pos


    def sort_wid(self,char *fdir,int index):

        '''
        在 wid 中进行排序 
        '''
         
        self.init(fdir,index)


        #初始化 wid_sort
        #此处使用了效率较低的重复初始化class
        #可以改进!!!!!!!!!!!!!!!!!!!
        
        #需要同时修改 长度 ??????????????????????????
        hitSort = hit_sort()

        hitSort.init(self.hit_list,self.length)

        #对wid进行快速排序
        print 'begin to sort in wid'

        hitSort.sort_in_wid(0,self.length-1)

        #wid已经排序完毕
        #开始扫描list 
        #在同一个wid内进行docid排序
        #需要确定边界
        cdef:
            int cur_wid
            int i = 0
            int cur_step
            int cur_sco_step

            int j = 0
            int cur_score

        #从最小的wid开始扫描排序

        cur_wid = self.hit_list[0].wordID

        print 'sort in wordid'

        #self.show()

        #初始索引
        cur_step = 0

        while i < self.width[index]:
            #开始扫描 hit_list
            #在整个文件中进行扫描
            if self.hit_list[i].wordID == cur_wid:
                #如果 wid 相同 则持续进行扫描
                pass

            else:
                #i为 同一个 wid 内的docid数量
                #对 同一个 wid 范围内 (cur_step i) 进行 did排序
                #将 wordID 推进
                cur_wid = self.hit_list[i].wordID

                #print 'the did scope is'
                #print cur_step,i-1

                hitSort.sort_in_did(cur_step , i-1)

                #开始在docid排序后
                #进行根据scoreid的排序
                j=cur_step
                cur_sco_step=j
                
                #确定了 wid
                #在同一个 did 内进行排序
                #开始对 score 进行排序
                cur_did = self.hit_list[cur_step].docID

                while j < i:
                    #对 每个docid内的score进行排序
                    #在 整个wid内进行排序 (cur_step j)
                    if self.hit_list[j].docID == cur_did:
                        pass
                    else:

                        cur_did = self.hit_list[j].docID
                        hitSort.sort_in_sco(cur_sco_step,j-1)
                        cur_sco_step = j

                    j+=1

                cur_step = i

            i+=1

        print 'sort ok'



    def save(self,char *ph,int index):
        
        '''
        将 hit_list进行排序
        '''
        fn = ph + str(index) + '.hit'
        cdef char *fname =  fn

        print 'the fname is',fname

        cdef FILE *fp=<FILE *>fopen(fname,"wb")
        print 'begin to save'

        print 'begin to write'

        fwrite(self.hit_list , sizeof(Hit), self.length ,fp)

        fclose(fp)




