"""
    add_genotypes(mme::MME,M,G;header=false,center=true,rowID=false,G_is_marker_variance=false,df=4)
* Get marker informtion from an nxp Matrix M of genotypes (Array or DataFrame),
  where n is the number of individuals and p is the number of markers. This matrix needs to be column-wise sorted by marker positions.
* rowID is a vector of individual IDs, e.g.,rowID=[\"a1\",\"b2\",\"c1\"]; if it is omitted, IDs will be set to 1:n
* header is a header vector such as ["id"; "mrk1"; "mrk2";...;"mrkp"]. If omitted, marker names will be set to 1:p
* **G** defaults to the genetic variance with degree of freedom **df**=4.0.

"""
function add_genotypes(mme::MME,M::Union{Array{Float64,2},DataFrames.DataFrame},G=false;rowID=false,header=false,center=true,G_is_marker_variance=false,df=4)
    if length(rowID) != size(M,1)
        rowID = string.(1:size(M,1))
        printstyled("The individual IDs is set to 1,2,...,#observations\n",bold=true)
    end
    if length(header) != (size(M,2)+1)
        header = ["id"; string.(1:size(M,2))]
        printstyled("The header (marker IDs) is set to 1,2,...,#markers\n",bold=true)
    end
    mme.M   = readgenotypes(M,rowID = rowID, header=header, center=center)
    if G_is_marker_variance == true
        mme.M.G = G
    else
        mme.M.genetic_variance = G
    end
    if mme.nModels == 1 #?move to set_marker_hyperparameters_variances_and_pi?
        mme.df.marker = Float64(df)
    else
        νG0   = Float64(df) + mme.nModels
        mme.df.marker = νG0 #final df for inverse wisahrt
    end
    println(size(mme.M.genotypes,2), " markers on ",size(mme.M.genotypes,1)," individuals were added.")
end

"""
    add_genotypes(mme::MME,file,G;separator=' ',header=true,center=true,G_is_marker_variance=false,df=4.0)
* Get marker informtion from a genotype file. This file needs to be column-wise sorted by marker positions.
* **G** defaults to the genetic variance with degree of freedom **df**=4.0.
* File format:

```
Animal,marker1,marker2,marker3,marker4,marker5
S1,1,0,1,1,1
D1,2,0,2,2,1
O1,1,2,0,1,0
O3,0,0,2,1,1
```
"""
function add_genotypes(mme::MME,file,G=false;separator=',',header=true,center=true,G_is_marker_variance=false,df=4)
    mme.M   = readgenotypes(file;separator=separator,header=header,center=center)
    if G_is_marker_variance == true
        mme.M.G = G
    else
        mme.M.genetic_variance = G
    end
    if mme.nModels == 1 #?move to set_marker_hyperparameters_variances_and_pi?
        mme.df.marker = Float64(df)
    else
        νG0   = Float64(df) + mme.nModels
        mme.df.marker = νG0 #final df for inverse wisahrt
    end
    println(size(mme.M.genotypes,2), " markers on ",size(mme.M.genotypes,1)," individuals were added.")
end

################################################################################
#
# convert genotype file or matrix to struct Genotypes in MME
#
################################################################################
#1)load genotypes from a text file (1st column: individual IDs; 1st row: marker IDs (optional))
function readgenotypes(file::AbstractString;separator=',',header=true,center=true)
    printstyled("The delimiter in ",split(file,['/','\\'])[end]," is \'",separator,"\'.\n",bold=false,color=:green)
    printstyled("The header (marker IDs) is ",(header ? "provided" : "not provided")," in ",split(file,['/','\\'])[end],".\n",bold=false,color=:green)

    #get marker IDs
    myfile = open(file)
    row1   = split(readline(myfile),[separator,'\n'],keepempty=false)
    if header==true
      markerID=string.(row1[2:end])  #skip header
    else
      markerID=string.(1:length(row1[2:end]))
    end
    #set type for each column
    ncol= length(row1)
    etv = Array{DataType}(undef,ncol)
    fill!(etv,Float64)
    etv[1]=String
    close(myfile)
    #read a large genotype file
    df        = CSV.read(file,types=etv,delim = separator,header=false,skipto=(header==true ? 2 : 1))
    obsID     = map(string,df[!,1])
    genotypes = map(Float64,convert(Matrix,df[!,2:end]))
    #preliminary summary of genotype
    nObs,nMarkers = size(genotypes)       #number of individuals and molecular markers
    markerMeans   = center==true ? center!(genotypes) : center(genotypes) #centering genotypes or not
    p             = markerMeans/2.0       #allele frequency
    sum2pq        = (2*p*(1 .- p)')[1,1]  #∑2pq

    return Genotypes(obsID,markerID,nObs,nMarkers,p,sum2pq,center,genotypes)
end

#2)load genotypes from Array or DataFrames (no individual IDs; no marker IDs (header))
function readgenotypes(M::Union{Array{Float64,2},Array{Any,2},DataFrames.DataFrame};rowID=false,header=false,center=true)
    if length(header) != (size(M,2)+1)
        header = ["id"; string.(1:size(M,2))]
        printstyled("The marker IDs are set to 1,2,...,#markers\n",bold=true)
    end
    if length(rowID) != size(M,1)
        rowID = string.(1:size(M,1))
        printstyled("The individual IDs is set to 1,2,...,#observations\n",bold=true)
    end
    markerID  = string.(header[2:end])
    obsID     = map(string,rowID)
    genotypes = map(Float64,convert(Matrix,M))
    #preliminary summary of genotype (duplication of the function above)
    nObs,nMarkers = size(genotypes)       #number of individuals and molecular markers
    markerMeans   = center==true ? center!(genotypes) : center(genotypes) #centering genotypes or not
    p             = markerMeans/2.0       #allele frequency
    sum2pq        = (2*p*(1 .- p)')[1,1]  #∑2pq

    return Genotypes(obsID,markerID,nObs,nMarkers,p,sum2pq,center,genotypes)
end
